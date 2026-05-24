
pretty-json: 
	jq . starlink_pops_airports.geojson > starlink_pops_airports.geojson.tmp && mv starlink_pops_airports.geojson.tmp starlink_pops_airports.geojson

refresh-aws-directconnect-regions:
	rm -f aws/directconnect*.json
	bash fetch-directconnect-locations.sh 