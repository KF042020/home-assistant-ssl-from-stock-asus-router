# ARG BUILD_FROM
FROM homeassistant/amd64-base:latest

RUN apk update
RUN apk add openssh

# Copy data for add-on
# COPY run.sh /
# RUN chmod a+x /run.sh

# CMD [ "/run.sh" ]
COPY run.sh /etc/services.d/asus-ssl/run
RUN chmod +x /etc/services.d/asus-ssl/run
