#!/bin/sh -e

: ${AWS_ACCESS_KEY_ID:?}
: ${AWS_SECRET_ACCESS_KEY:?}
: ${AWS_DEFAULT_REGION:?}

: ${IMAGE_ID:=ami-63b25203}
: ${INSTANCE_TYPE:=c4.large}
: ${VPC_SUBNET_ID:?}
: ${SECURITY_GROUP_ID:?}
: ${KEY_NAME:?}
: ${PRIVATE_KEY_FILE:?}
: ${GLOWROOT_DIST_ZIP:=../glowroot/agent-parent/distribution/target/glowroot-*-dist.zip}
: ${CLOCKSOURCE:=tsc}

: ${TOMCAT_HOME:=/usr/share/tomcat8}
: ${TOMCAT_SERVICE_NAME:=tomcat8}

echo creating instance ...
instance_id=`aws ec2 run-instances --image-id $IMAGE_ID --count 1 --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --subnet-id $VPC_SUBNET_ID --security-group-id $SECURITY_GROUP_ID --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":16}}]' | grep InstanceId | cut -d '"' -f4`

# suppress stdout (but not stderr)
aws ec2 create-tags --resources $instance_id --tags Key=Name,Value=demo.glowroot.org > /dev/null

echo instance created: $instance_id

while
  public_dns_name=`aws ec2 describe-instances --instance-ids $instance_id --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].PublicDnsName' --output text`
  [ ! $public_dns_name ]
do
  echo waiting for instance to start ...
  sleep 1
done

echo instance started: $public_dns_name

while
  # intentionally suppress both stdout and stderr
  ssh -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no ec2-user@$public_dns_name echo &> /dev/null
  [ "$?" != "0" ]
do
  echo waiting for sshd to start ...
  sleep 1
done

setup_script="
sudo yum -y install java-1.8.0-openjdk-devel
echo 2 | sudo alternatives --config java
sudo yum -y install $TOMCAT_SERVICE_NAME
sudo yum -y install mysql-server
sudo service mysqld start
sudo chkconfig mysqld on
mysqladmin -u root password password
sudo yum -y install git
echo $CLOCKSOURCE | sudo tee /sys/devices/system/clocksource/clocksource0/current_clocksource > /dev/null

curl http://archive.apache.org/dist/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz | tar xz
export PATH=\$PATH:\$PWD/apache-maven-3.3.9/bin

./setup.sh

sudo cp config.json $TOMCAT_HOME/glowroot
sudo chown -R tomcat:tomcat $TOMCAT_HOME/glowroot

jvm_args=\"-javaagent:$TOMCAT_HOME/glowroot/glowroot.jar -javaagent:$TOMCAT_HOME/heatclinic/spring-instrument.jar -XX:+UseG1GC -Druntime.environment=production -Ddatabase.url=jdbc:mysql://localhost:3306/heatclinic?useUnicode=true&characterEncoding=utf8 -Ddatabase.user=heatclinic -Ddatabase.password=heatclinic -Ddatabase.driver=org.mariadb.jdbc.Driver -Dproperty-shared-override=$TOMCAT_HOME/heatclinic/heatclinic.properties -Dglowroot.internal.googleAnalyticsTrackingId=UA-35673195-2 -Dglowroot.internal.ui.workerThreads=10 -Dglowroot.internal.h2.cacheSize=131072\"
echo CATALINA_OPTS=\\\"\$jvm_args\\\" | sudo tee /etc/sysconfig/$TOMCAT_SERVICE_NAME > /dev/null

sudo chkconfig $TOMCAT_SERVICE_NAME on
sudo service $TOMCAT_SERVICE_NAME start

sudo yum -y install postfix
sudo chkconfig postfix on

sudo yum -y install nginx
sudo chkconfig nginx on

sudo tee /etc/nginx/nginx.conf > /dev/null <<'EOF'
events {
    worker_connections 1024;
}
http {
    log_format glowroot '\$remote_addr \$http_x_forwarded_for [\$time_local] '
                        '"\$request" \$status \$body_bytes_sent \$request_time '
                        '"\$http_referer" "\$http_user_agent"';
    access_log /var/log/nginx/access.log glowroot;
    server {
        location / {
            proxy_pass http://localhost:4000;
        }
    }
}
EOF

sudo service nginx start

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

scp -rC -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no *.sh *.json *.properties simulations ec2-user@$public_dns_name:.
scp -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no $GLOWROOT_DIST_ZIP ec2-user@$public_dns_name:glowroot-dist.zip

# -tt is to force a tty which is needed to run sudo
ssh -tt -i $PRIVATE_KEY_FILE -o StrictHostKeyChecking=no ec2-user@$public_dns_name "$setup_script"
