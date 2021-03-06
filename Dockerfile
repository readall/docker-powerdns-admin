FROM alpine:3.11 AS builder
LABEL maintainer="k@ndk.name"

ARG BUILD_DEPENDENCIES="build-base \
    libffi-dev \
    libxml2-dev \
    mariadb-connector-c-dev \
    openldap-dev \
    py3-pip \
    python3-dev \
    xmlsec-dev \
    yarn \
    git"

ENV LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    FLASK_APP=/build/powerdnsadmin/__init__.py

# Get dependencies
RUN apk add --no-cache ${BUILD_DEPENDENCIES} && \
    ln -s /usr/bin/pip3 /usr/bin/pip


# Get the source from the master branch
RUN git clone https://github.com/ngoduykhanh/PowerDNS-Admin.git /build/
RUN cd /build && git checkout tags/v0.2.2

WORKDIR /build

# Get application dependencies
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# Prepare assets
RUN yarn install --pure-lockfile --production && \
    yarn cache clean && \
    sed -i -r -e "s|'cssmin',\s?'cssrewrite'|'cssmin'|g" /build/powerdnsadmin/assets.py && \
    flask assets build

RUN mv /build/powerdnsadmin/static /tmp/static && \
    mkdir /build/powerdnsadmin/static && \
    cp -r /tmp/static/generated /build/powerdnsadmin/static && \
    cp -r /tmp/static/assets /build/powerdnsadmin/static && \
    cp -r /tmp/static/img /build/powerdnsadmin/static && \
    find /tmp/static/node_modules -name 'fonts' -exec cp -r {} /build/powerdnsadmin/static \; && \
    find /tmp/static/node_modules/icheck/skins/square -name '*.png' -exec cp {} /build/powerdnsadmin/static/generated \;

RUN { \
      echo "from flask_assets import Environment"; \
      echo "assets = Environment()"; \
      echo "assets.register('js_login', 'generated/login.js')"; \
      echo "assets.register('js_validation', 'generated/validation.js')"; \
      echo "assets.register('css_login', 'generated/login.css')"; \
      echo "assets.register('js_main', 'generated/main.js')"; \
      echo "assets.register('css_main', 'generated/main.css')"; \
    } > /build/powerdnsadmin/assets.py

# Move application
RUN mkdir -p /app && \
    cp -r /build/migrations/ /build/powerdnsadmin/ /build/run.py /app

COPY docker_config.py /app/powerdnsadmin/default_config.py

# Cleanup
RUN pip install pip-autoremove && \
    pip-autoremove cssmin -y && \
    pip-autoremove jsmin -y && \
    pip-autoremove pytest -y && \
    pip uninstall -y pip-autoremove && \
    apk del ${BUILD_DEPENDENCIES}


# Build image
FROM alpine:3.11

ENV FLASK_APP=/app/powerdnsadmin/__init__.py

RUN apk add --no-cache mariadb-connector-c postgresql-client py3-gunicorn py3-psycopg2 xmlsec tzdata bash mysql-client && \
    addgroup -S pda && \
    adduser -S -D --no-create-home -G pda pda && \
    mkdir /data && \
    chown pda:pda /data

COPY --from=builder /usr/bin/flask /usr/bin/
COPY --from=builder /usr/lib/python3.8/site-packages /usr/lib/python3.8/site-packages/
COPY --from=builder --chown=pda:pda /app /app/

COPY entrypoint.sh /usr/bin/
RUN chmod 755 /usr/bin/entrypoint.sh

WORKDIR /app

EXPOSE 80/tcp
HEALTHCHECK CMD ["wget","--output-document=-","--quiet","--tries=1","http://127.0.0.1/"]
ENTRYPOINT ["bash", "/usr/bin/entrypoint.sh"]
CMD ["gunicorn","powerdnsadmin:create_app()","--user","pda","--group","pda"]