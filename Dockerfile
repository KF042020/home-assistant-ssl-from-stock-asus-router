# ARG BUILD_FROM
FROM alpine:3.19

RUN apk update
RUN apk add --no-cache openssh-client jq coreutils

# Copy data for add-on
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
