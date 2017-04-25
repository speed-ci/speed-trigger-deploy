FROM docker-artifactory-poc.sln.nc/docker:17.03.0-ce

RUN apk --no-cache add git curl jq bash

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

CMD ["/docker-entrypoint.sh"]