JAVA_VER=$(java -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*".*/\1\2/p;')
if [ "$JAVA_VER" -ge 170 ]; then 
	echo "ok, java is 17 or newer"
else 
	echo "not ok, java is older than 17"
	exit 1
fi


mkdir downloads
echo "downloading Apache Spark"
curl https://dlcdn.apache.org/spark/spark-3.3.1/spark-3.3.1-bin-hadoop3.tgz --silent --output downloads/spark-3.3.1-bin-hadoop3.tgz
echo "downloading Apache Iceberg runtime for Spark"
curl https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.3_2.12/1.1.0/iceberg-spark-runtime-3.3_2.12-1.1.0.jar --silent --output downloads/iceberg-spark-runtime-3.3_2.12-1.1.0.jar
echo "downloading Apache Derby"
curl https://dlcdn.apache.org//db/derby/db-derby-10.16.1.1/db-derby-10.16.1.1-lib.tar.gz --silent --output downloads/db-derby-10.16.1.1-lib.tar.gz
echo "downloading hive-schema"
curl https://raw.githubusercontent.com/apache/hive/master/metastore/scripts/upgrade/derby/hive-schema-2.3.0.derby.sql --silent --output ./hive-schema-2.3.0.derby.sql
echo "downloading hive-txn-schema"
curl https://raw.githubusercontent.com/apache/hive/master/metastore/scripts/upgrade/derby/hive-txn-schema-2.3.0.derby.sql --silent --output ./hive-txn-schema-2.3.0.derby.sql
mkdir components
echo "unpacking Apache Spark"
tar zxf ./downloads/spark-*-bin-*.tgz -C ./components
echo "adding Iceberg runtime to Spark"
cp ./downloads/iceberg-*.jar ./components/spark-*/jars
echo "unpacking Derby"
tar zxf ./downloads/db-derby-*.tar.gz -C ./components
echo "adding Derby jars to Spark"
cp components/db-derby-*-lib/lib/* components/spark-*/jars/

echo "Apache Spark Metastore init"
cat << EOF > ./init_metastore.sql
CONNECT 'jdbc:derby:metastore-derby;create=true';
RUN './hive-schema-2.3.0.derby.sql';
EOF

java -jar ./components/db-derby-10.16.1.1-lib/lib/derbyrun.jar ij 'init_metastore.sql' > metastore_init.log

echo "creating start/stop scripts"
mkdir data
cat << EOF > start_datalake.sh
#!/bin/sh
$PWD/components/spark-3.3.1-bin-hadoop3/sbin/start-thriftserver.sh \
--conf spark.sql.extensions="org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions" \
--conf spark.sql.catalog.my_catalog=org.apache.iceberg.spark.SparkCatalog \
--conf spark.sql.catalog.my_catalog.warehouse=file://$PWD/warehouse \
--conf spark.sql.catalog.my_catalog.default-namespace=default \
--conf spark.sql.warehouse.dir=file://$PWD/data \
--conf hive.metastore.warehouse.dir=file://$PWD/data \
--conf spark.sql.catalogImplementation=hive \
--conf spark.hadoop.javax.jdo.option.ConnectionURL="jdbc:derby:$PWD/metastore-derby" \
--conf spark.hadoop.javax.jdo.option.ConnectionDriverName=org.apache.derby.jdbc.EmbeddedDriver \
--conf spark.sql.catalog.spark_catalog=org.apache.iceberg.spark.SparkSessionCatalog \
--conf spark.sql.catalog.spark_catalog.warehouse.dir=file://$PWD/warehouse \
--conf spark.eventLog.enabled=true \
--conf spark.eventLog.dir=file://$PWD/spark-events \
--conf spark.history.fs.logDirectory= file://$PWD/spark-events \
--conf spark.sql.thriftServer.incrementalCollect=true \
--conf spark.sql.ansi.enabled=true
EOF

chmod +x start_datalake.sh

cat << EOF > stop_datalake.sh
#!/bin/sh
$PWD/components/spark-3.3.1-bin-hadoop3/sbin/stop-thriftserver.sh
EOF

chmod +x stop_datalake.sh

mkdir spark-events

cat << EOF > sql_console.sh
$PWD/components/spark-3.3.1-bin-hadoop3/bin/beeline -u 'jdbc:hive2://localhost:10000/'
EOF

chmod +x sql_console.sh

echo "cleaning up"
rm -rf downloads
rm *.sql
echo "Done."
