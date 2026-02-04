switch-java8

mvn -f ~/src/apps/server/ipg-mock-cxf clean install

cp ~/src/apps/server/ipg-mock-cxf/war/target/ipg-mock*.jar ~/dotfiles/scripts/ipg-mock/ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar
scp ~/dotfiles/scripts/ipg-mock/ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar fransico.yanes@dev7-cosbatch01.dev.pdx10.clover.network:~

chmod +x ipg-mock-cxf-war-1.0-SNAPSHOT-war-exec.jar

kill -15 `cat ipg-mock.pid`
ps -aux | grep ipg
rm -rf .extract log ipg-mock.log ipg-mock.pid

./start.sh -c
cat ipg-mock.log 
cat ipg-mock.log >> cat_output.txt
rm cat_output.txt && scp fransico.yanes@dev7-cosbatch01.dev.pdx10.clover.network:~/cat_output.txt .
