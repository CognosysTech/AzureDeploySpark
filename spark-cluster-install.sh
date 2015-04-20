#!/bin/bash

### Cognosys Technologies
### 
### Warning! This script partitions and formats disk information be careful where you run it
###          This script is currently under development and has only been tested on Ubuntu images in Azure
###          This script is not currently idempotent and only works for provisioning at the moment

### Remaining work items
### -Alternate discovery options (Azure Storage)
### -Implement Idempotency and Configuration Change Support
### -Implement OS Disk Striping Option (Currenlty using multiple spark data paths)
### -Implement Non-Durable Option (Put data on resource disk)
### -Configure Work/Log Paths
### -Recovery Settings (These can be changed via API)

help()
{
    #TODO: Add help text here
    echo "This script installs spark cluster on Ubuntu"
    echo "Parameters:"
    echo "-k spark version like 1.2.1"
    echo "-m master 1 slave 0"
    echo "-h view this help content"
}

echo "Begin execution of spark script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ];
then
    echo "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? -eq $SUCCESS ];
then
  echo "${HOSTNAME}found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hsots file if not there
  echo "127.0.0.1 $(hostname)" >> /etc/hosts
  echo "hostname ${HOSTNAME} added to /etc/hosts"
fi

#Script Parameters
SPK_VERSION="1.2.1"
MASTER1SLAVE0="1"

#Loop through options passed
while getopts :k:m:h optname; do
    echo "Option $optname set with value ${OPTARG}"
  case $optname in
    k)  #spark version
      SPK_VERSION=${OPTARG}
      ;;
    m)  #Master 1 Slave 0
      MASTER1SLAVE0=${OPTARG}
      ;;
    h)  #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

install_pre()
{
	sudo  apt-get -y update
	 
	echo "Installing Java"
	add-apt-repository -y ppa:webupd8team/java
	apt-get -y update 
	echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
	echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
	apt-get -y install oracle-java7-installer

	sudo ntpdate pool.ntp.org
	 
	sudo apt-get -y install ntp
	 
	sudo apt-get -y install python-software-properties 

	sudo apt-get -y update 
	
	sudo apt-get -y install git

}

# Install spark
install_spark()
{

	##Second download and install Apache Spark

	cd ~
	 
	mkdir /usr/local/azurespark
	 
	cd /usr/local/azurespark/
	 
	wget http://mirror.tcpdiag.net/apache/spark/spark-1.2.1/spark-1.2.1.tgz
	 
	gunzip -c spark-1.2.1.tgz | tar -xvf -
	
	mv spark-1.2.1 ../

	cd ../spark-1.2.1/
	
	# this will take quite a while
	sudo sbt/sbt assembly
	 
	cd ..
	 
	#sudo cp -Rp spark-1.2.1 /usr/local/
	 
	cd /usr/local/
	 
	sudo ln -s spark-1.2.1 spark

#	Third create a spark user with proper privileges and ssh keys.

	sudo addgroup spark
	sudo useradd -g spark spark
	sudo adduser spark sudo
	sudo mkdir /home/spark
	sudo chown spark:spark /home/spark
	 
#	Add to sudoers file:
	 
	echo "spark ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-cloud-init-users
	 
	sudo chown -R spark:spark /usr/local/spark/
	
	# setting passwordless ssh for root also remove later
        rm ~/.ssh/id_rsa 
	ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

#	ssh-keygen -t rsa -P ""
#	cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
	
#exit
#	Fourth setup some Apache Spark working directories with proper user permissions

	sudo mkdir -p /srv/spark/{logs,work,tmp,pids}
	 
	sudo chown -R spark:spark /srv/spark
	 
	sudo chmod 4755 /srv/spark/tmp

#	Fifth let�s do a quick test
#	cd /usr/local/spark	 
#	bin/run-example SparkPi 10

#	Now lets adjust some Spark configuration files

	cd /usr/local/spark/conf/
	cp -p spark-env.sh.template spark-env.sh
	touch spark-env.sh  
	 
#	========================================================
#	echo 'SPARK-ENV.SH (ADD BELOW)' >> spark-env.sh

# Make sure to put your change SPARK_PUBLIC_DNS=�PUBLIC IP� to your Public IP
	 
	echo 'export SPARK_WORKER_CORES="2"' >> spark-env.sh
	echo 'export SPARK_WORKER_MEMORY="1g"' >> spark-env.sh
	echo 'export SPARK_DRIVER_MEMORY="1g"' >> spark-env.sh
	echo 'export SPARK_REPL_MEM="2g"' >> spark-env.sh
	echo 'export SPARK_WORKER_PORT=9000' >> spark-env.sh
	echo 'export SPARK_CONF_DIR="/usr/local/spark/conf"' >> spark-env.sh
	echo 'export SPARK_TMP_DIR="/srv/spark/tmp"' >> spark-env.sh
	echo 'export SPARK_PID_DIR="/srv/spark/pids"' >> spark-env.sh
	echo 'export SPARK_LOG_DIR="/srv/spark/logs"' >> spark-env.sh
	echo 'export SPARK_WORKER_DIR="/srv/spark/work"' >> spark-env.sh
	echo 'export SPARK_LOCAL_DIRS="/srv/spark/tmp"' >> spark-env.sh
	echo 'export SPARK_COMMON_OPTS="$SPARK_COMMON_OPTS -Dspark.kryoserializer.buffer.mb=32 "' >> spark-env.sh
	echo 'LOG4J="-Dlog4j.configuration=file://$SPARK_CONF_DIR/log4j.properties"' >> spark-env.sh
	echo 'export SPARK_MASTER_OPTS=" $LOG4J -Dspark.log.file=/srv/spark/logs/master.log "' >> spark-env.sh
	echo 'export SPARK_WORKER_OPTS=" $LOG4J -Dspark.log.file=/srv/spark/logs/worker.log "' >> spark-env.sh
	echo 'export SPARK_EXECUTOR_OPTS=" $LOG4J -Djava.io.tmpdir=/srv/spark/tmp/executor "' >> spark-env.sh
	echo 'export SPARK_REPL_OPTS=" -Djava.io.tmpdir=/srv/spark/tmp/repl/\$USER "' >> spark-env.sh
	echo 'export SPARK_APP_OPTS=" -Djava.io.tmpdir=/srv/spark/tmp/app/\$USER "' >> spark-env.sh
	echo 'export PYSPARK_PYTHON="/usr/bin/python"' >> spark-env.sh
	echo 'SPARK_PUBLIC_DNS="PUBLIC IP"' >> spark-env.sh
	echo 'export SPARK_WORKER_INSTANCES=2' >> spark-env.sh
	#=========================================================
	 
	cp -p spark-defaults.conf.template spark-defaults.conf
	touch spark-defaults.conf
	 
	#=========================================================
	#SPARK-DEFAULTS (ADD BELOW)
	 
	echo 'spark.master            spark://localhost:7077' >> spark-defaults.conf
	echo 'spark.executor.memory   512m' >> spark-defaults.conf
	echo 'spark.eventLog.enabled  true' >> spark-defaults.conf
	echo 'spark.serializer        org.apache.spark.serializer.KryoSerializer' >> spark-defaults.conf
	 
	#================================================================

	#Time to start Apache Spark up

	sudo su spark
	rm ~/.ssh/id_rsa 
	ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

	ssh localhost
 
	cd /usr/local/spark/sbin
	if [ ${MASTER1SLAVE0} -eq "1" ];
	    then
		./start-master.sh
	    else
		./start-slaves.sh
	fi
	#Note to stop processes do:
	 
	#./stop-slaves.sh
	 
	#./stop-master.sh
}

# Primary Install Tasks
#########################
#NOTE: These first three could be changed to run in parallel
#      Future enhancement - (export the functions and use background/wait to run in parallel)

#Install Pre requisites
#------------------------
install_pre

#Install spark
#-----------------------
install_spark

#========================= END ==================================

