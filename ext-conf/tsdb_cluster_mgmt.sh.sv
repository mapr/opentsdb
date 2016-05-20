

for metric in $(curl -XGET http://localhost:4242/api/'suggest?type=metrics&max=500' | sed -e 's/\[//;s/\]//;s/\,/ /g') ; do
    tsdb scan --delete 2000/01/01 $(date --date='2 weeks ago' +'%Y/%m/%d') sum $metric 
done >/dev/null
