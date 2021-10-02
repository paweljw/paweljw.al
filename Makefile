serve:
	hugo server -w --noHTTPCache --disableFastRender -v

deploy:
	hugo
#	aws s3 rm --recursive --profile paweljwal "s3://paweljw.al/"
	aws s3 cp --recursive --profile paweljwal dist "s3://paweljw.al" --acl bucket-owner-full-control
