#!/bin/sh -e

: ${AWS_ACCESS_KEY_ID:?}
: ${AWS_SECRET_ACCESS_KEY:?}
: ${AWS_DEFAULT_REGION:?}

: ${HOST:=ec2-54-68-196-98.us-west-2.compute.amazonaws.com}
: ${KEY_NAME:?}
: ${PRIVATE_KEY_FILE:?}
: ${GLOWROOT_DIST_ZIP:=../glowroot/agent-parent/distribution/target/glowroot-*-dist.zip}

: ${TOMCAT_HOME:=/usr/share/tomcat8}
: ${TOMCAT_SERVICE_NAME:=tomcat8}

update_script="
sudo service tomcat8 stop

# do not delete data folder
sudo rm -rf /usr/share/tomcat8/glowroot/plugins
sudo rm -f /usr/share/tomcat8/glowroot/glowroot.log
sudo unzip -o glowroot-dist.zip -d $TOMCAT_HOME
sudo cp config.json $TOMCAT_HOME/glowroot
sudo cp admin.json $TOMCAT_HOME/glowroot
sudo chown -R tomcat:tomcat $TOMCAT_HOME/glowroot

jvm_args=\"-javaagent:$TOMCAT_HOME/glowroot/glowroot.jar -javaagent:$TOMCAT_HOME/heatclinic/spring-instrument.jar -XX:+UseG1GC -Druntime.environment=production -Ddatabase.url=jdbc:mysql://localhost:3306/heatclinic?useUnicode=true&characterEncoding=utf8 -Ddatabase.user=heatclinic -Ddatabase.password=heatclinic -Ddatabase.driver=org.mariadb.jdbc.Driver -Dproperty-shared-override=$TOMCAT_HOME/heatclinic/heatclinic.properties -Dglowroot.internal.googleAnalyticsTrackingId=UA-35673195-2 -Dglowroot.internal.ui.workerThreads=10 -Dglowroot.internal.h2.cacheSize=131072\"
echo CATALINA_OPTS=\\\"\$jvm_args\\\" | sudo tee /etc/sysconfig/$TOMCAT_SERVICE_NAME > /dev/null

sudo sh -c \"rm /usr/share/tomcat8/logs/*\"

sudo service tomcat8 start

# wait for tomcat to start
while
  sleep 5
  sudo sh -c \"grep 'Server startup' $TOMCAT_HOME/logs/catalina.*.log\"
  [ \"\$?\" != \"0\" ]
do
  echo waiting for tomcat to start ...
done

# TODO pipe to rolling log files
nohup gatling/bin/gatling.sh --simulations-folder simulations --results-folder results -s HeatClinicSimulation > /dev/null &
nohup ./randomly-lock-table.sh > randomly-lock-table.log &
nohup ./randomly-kill-sessions.sh > randomly-kill-sessions.log &

sleep 5
"

scp -rC -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no *.sh *.json *.properties simulations ec2-user@$HOST:.
scp -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no $GLOWROOT_DIST_ZIP ec2-user@$HOST:glowroot-dist.zip

# these pkills kill the ssh also, which is why they are all run separately
#
# need "|| true" at end because these ssh command return failure and running under "/bin/sh -e"
ssh -tt -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no ec2-user@$HOST "pkill -f gatling" || true
ssh -tt -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no ec2-user@$HOST "pkill -f randomly-lock-table" || true
ssh -tt -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no ec2-user@$HOST "pkill -f randomly-kill-sessions" || true

# -tt is to force a tty which is needed to run sudo
ssh -tt -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no ec2-user@$HOST "$update_script"
