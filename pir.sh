#! /bin/bash

# Part of the "Coding While Drinking" collection. Minimal effort, maximum fun. (ie, the opposite of my day job)

# I publish things like this hoping it will help someone else. This in no way reflects the quality of work I'm actually paid for. 
# May 2019, Matt Hallacy

# GPIO you have the PIR motion sensor tied to
GPIO="4"
# Your MQTT host
MQTTHOST="poptix.net"
# The MQTT name of your (preferably Sonoff-Tasmota) device
MQTTDEVICE="home_garage_outlet"
# A space separated list of bluetooth devices (phones typically) that are authorized
BTDEVICES="aa:bb:cc:dd:ee:ff"
# How many seconds until we turn off the switch
OFFDELAY=900

# If you fill these out they will send to pushover.net

# pushover.net app token
POTOKEN=""
# pushover.net user token
POUSER=""

if [ -e ~/.garage-pir ] ; then 
	source ~/.garage-pir
fi

if [ ! -e /sys/class/gpio/gpio$GPIO/ ]; then
	echo $GPIO > /sys/class/gpio/export
fi

echo in > /sys/class/gpio/gpio$GPIO/direction

MQTTSTATE=`mosquitto_sub -h $MQTTHOST -v -t "stat/$MQTTDEVICE/POWER" -C 1 | awk '{ print $2 }'` 
echo Startup switch state $MQTTSTATE 
if [ ${MQTTSTATE} = "ON" ]; then 
	LASTSTATE=1
	printf -v LASTON '%(%s)T' 
else
	LASTSTATE=0 
	LASTON=0 
fi 

while [ 1 ]; do
	STATE=`cat /sys/class/gpio/gpio$GPIO/value` 
	if [ ${STATE} -eq 1 ]; then
		#We don't want to turn off unless there has been no motion for 15 minutes, save the last activity
		printf -v LASTON '%(%s)T' 
	fi 
	if [ 1 ]; then #${STATE} -ne ${LASTSTATE} ]; then 
		if [ $STATE -eq 0 ]; then 
			echo No motion, check timer 
			printf -v NOW '%(%s)T'
			#If the last motion was more than 15 minutes ago, let it turn off.
			echo $LASTON $((LASTON + $OFFDELAY)) $NOW 
			if [ $((LASTON + $OFFDELAY)) -le $NOW ]; then
				echo Turning Off
				mosquitto_pub -u $USER -P $PASS -h $MQTTHOST -t cmnd/$MQTTDEVICE/power -m $STATE 
				LASTSTATE=$STATE
			fi
		else
  			NEARBY=0
			if [ -n ${BTDEVICES} ]; then
				#Ping the bluetooth devices (phones..) of authorized people
    				for i in `echo $BTDEVICES`; do
					l2ping -d 0 -v $i -c 3 
					RESULT=$? 
					if [ $RESULT -eq 0 ]; then 
						NEARBY=1 
					fi 
				done 
			else
				NEARBY=1
			fi
			if [ $NEARBY -eq 1 ]; then
				echo Turning On
				mosquitto_pub -u $USER -P $PASS -h $MQTTHOST -t cmnd/$MQTTDEVICE/power -m $STATE 
				LASTSTATE=$STATE
				# Calm the cameras to avoid unnecessary alerts
				wget -O /dev/null ${CALMDOWNURL}1
				wget -O /dev/null ${CALMDOWNURL}2
				wget -O /dev/null ${CALMDOWNURL}3
				wget -O /dev/null ${CALMDOWNURL}5
				wget -O /dev/null ${CALMDOWNURL}8
				sleep 60
			else
				echo Unauthorized visitor??
				if [ -n ${POUSER} ]; then
					curl -s --form "token=$POTOKEN" --form "user=$POUSER" --form "message=Unauthorized Garage motion detected!" https://api.pushover.net/1/messages.json
				fi
  			fi
		fi
	fi 
	sleep 1 
done
