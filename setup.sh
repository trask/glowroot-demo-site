#!/bin/sh -e

: ${TOMCAT_HOME:=/usr/share/tomcat8}
: ${TOMCAT_SERVICE_NAME:=tomcat8}

# download heatclinic
git clone https://github.com/BroadleafCommerce/DemoSite.git heatclinic
(cd heatclinic \
  && git checkout broadleaf-5.0.3-GA \
  && mvn package)

# download gatling
curl -o gatling.zip https://repo1.maven.org/maven2/io/gatling/highcharts/gatling-charts-highcharts-bundle/2.2.2/gatling-charts-highcharts-bundle-2.2.2-bundle.zip
unzip gatling.zip
mv gatling-charts-highcharts-* gatling
rm gatling.zip

# download mysql jdbc driver
curl -o mysql-connector-java.jar http://repo1.maven.org/maven2/mysql/mysql-connector-java/6.0.4/mysql-connector-java-6.0.4.jar

# create mysql user for heatclinic
mysql --user=root --password=password <<EOF
create user heatclinic@localhost identified by 'heatclinic';
create database heatclinic default character set utf8 default collate utf8_general_ci;
grant all privileges on heatclinic.* to heatclinic@localhost;
EOF

# install mysql jdbc driver
sudo cp mysql-connector-java.jar $TOMCAT_HOME/lib

# install glowroot somewhere tomcat can access
sudo unzip glowroot-dist.zip -d $TOMCAT_HOME
sudo chown -R tomcat:tomcat $TOMCAT_HOME/glowroot

# install spring-instrument javaagent somewhere tomcat can access
sudo mkdir -p $TOMCAT_HOME/heatclinic
sudo cp heatclinic/site/target/agents/spring-instrument.jar $TOMCAT_HOME/heatclinic/spring-instrument.jar

# install heatclinic war
sudo cp heatclinic/site/target/mycompany.war $TOMCAT_HOME/webapps/ROOT.war
sudo cp heatclinic/tomcat-server-conf/context.xml $TOMCAT_HOME/conf

# create directory that heatclinic uses for generating/caching static resources
sudo mkdir /broadleaf
sudo chown tomcat:tomcat /broadleaf

# build the database
sudo cp heatclinic-createdb.properties $TOMCAT_HOME/heatclinic/heatclinic.properties

jvm_args="-javaagent:$TOMCAT_HOME/heatclinic/spring-instrument.jar -XX:+UseG1GC -Druntime.environment=production -Ddatabase.url=jdbc:mysql://localhost:3306/heatclinic?useUnicode=true&characterEncoding=utf8 -Ddatabase.user=heatclinic -Ddatabase.password=heatclinic -Ddatabase.driver=com.mysql.cj.jdbc.Driver -Dproperty-shared-override=$TOMCAT_HOME/heatclinic/heatclinic.properties"
echo CATALINA_OPTS=\"$jvm_args\" | sudo tee /etc/sysconfig/$TOMCAT_SERVICE_NAME > /dev/null

sudo service $TOMCAT_SERVICE_NAME start

# wait for tomcat to start
while
  sleep 5
  sudo sh -c "grep 'Server startup' $TOMCAT_HOME/logs/catalina.*.log"
  [ "$?" != "0" ]
do
  echo waiting for tomcat to start ...
done

sudo service $TOMCAT_SERVICE_NAME stop

# copy extra heatclinic properties file somewhere tomcat can access
sudo cp heatclinic.properties $TOMCAT_HOME/heatclinic/heatclinic.properties
