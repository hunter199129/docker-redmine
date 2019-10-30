FROM ubuntu:xenial-20190222 AS add-apt-repositories

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y wget \
 && apt-key adv --keyserver keyserver.ubuntu.com --recv E1DD270288B4E6030699E45FA1715D88E1DF1F24 \
 && echo "deb http://ppa.launchpad.net/git-core/ppa/ubuntu xenial main" >> /etc/apt/sources.list \
 && apt-key adv --keyserver keyserver.ubuntu.com --recv 80F70E11F0F0D5F10CB20E62F5DA5F09C3173AA6 \
 && echo "deb http://ppa.launchpad.net/brightbox/ruby-ng/ubuntu xenial main" >> /etc/apt/sources.list \
 && apt-key adv --keyserver keyserver.ubuntu.com --recv 8B3981E7A6852F782CC4951600A6F0A3C300EE8C \
 && echo "deb http://ppa.launchpad.net/nginx/stable/ubuntu xenial main" >> /etc/apt/sources.list \
 && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
 && echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' > /etc/apt/sources.list.d/pgdg.list

FROM ubuntu:xenial-20190222

LABEL maintainer="sameer@damagehead.com"

ENV RUBY_VERSION=2.4 \
    REDMINE_VERSION=4.0.5 \
    REDMINE_USER="redmine" \
    REDMINE_HOME="/home/redmine" \
    REDMINE_LOG_DIR="/var/log/redmine" \
    REDMINE_ASSETS_DIR="/etc/docker-redmine" \
    RAILS_ENV=production

ENV REDMINE_INSTALL_DIR="${REDMINE_HOME}/redmine" \
    REDMINE_DATA_DIR="${REDMINE_HOME}/data" \
    REDMINE_BUILD_ASSETS_DIR="${REDMINE_ASSETS_DIR}/build" \
    REDMINE_RUNTIME_ASSETS_DIR="${REDMINE_ASSETS_DIR}/runtime"

COPY --from=add-apt-repositories /etc/apt/trusted.gpg /etc/apt/trusted.gpg

COPY --from=add-apt-repositories /etc/apt/sources.list /etc/apt/sources.list
COPY --from=add-apt-repositories /etc/apt/sources.list.d/pgdg.list /etc/apt/sources.list.d/
COPY Gemfile .

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      supervisor logrotate nginx mysql-client postgresql-client ca-certificates sudo tzdata \
      imagemagick subversion git cvs bzr mercurial darcs rsync ruby${RUBY_VERSION} locales openssh-client \
      gcc g++ make patch pkg-config gettext-base ruby${RUBY_VERSION}-dev libc6-dev zlib1g-dev libxml2-dev \
      libmysqlclient20 libpq5 libyaml-0-2 libcurl3 libssl1.0.0 uuid-dev xz-utils \
      libxslt1.1 libffi6 zlib1g gsfonts vim-tiny \
 && update-locale LANG=C.UTF-8 LC_MESSAGES=POSIX \
 && gem install --no-document bundler \
 ## Install gems for plugins
 && bundle config --global silence_root_warning 1 \
 && bundle install \
 && rm -rf /var/lib/apt/lists/*

## Install libreoffice
RUN apt update \
&& apt -y install libmysqlclient-dev libpq-dev libmagick++-dev \
&& apt -y install software-properties-common \
&& add-apt-repository ppa:libreoffice/ppa \
&& apt update  | grep packages \
&& apt -y install libreoffice --no-install-recommends \
&& apt -y install unzip

COPY assets/build/ ${REDMINE_BUILD_ASSETS_DIR}/

RUN bash ${REDMINE_BUILD_ASSETS_DIR}/install.sh

COPY assets/runtime/ ${REDMINE_RUNTIME_ASSETS_DIR}/

COPY assets/tools/ /usr/bin/

COPY entrypoint.sh /sbin/entrypoint.sh

RUN chmod 755 /sbin/entrypoint.sh \
 && sed -i '/session    required     pam_loginuid.so/c\#session    required   pam_loginuid.so' /etc/pam.d/cron

EXPOSE 80/tcp 443/tcp

WORKDIR ${REDMINE_INSTALL_DIR}

## Customize 
## Set encoding for csv output issue
RUN sed -e "s/general_csv_encoding: ISO-8859-1/general_csv_encoding: gb18030/" -i config/locales/en.yml
RUN sed -e "s/general_csv_encoding: Big5/general_csv_encoding: gb18030/" -i config/locales/zh-TW.yml
## Set index
RUN sed -e "s/root :to => 'welcome#index', :as => 'home'/root :to => 'projects#index', :as => 'home'/" -i config/routes.rb

## Plugins
COPY plugins.zip .
RUN mkdir plugins \
&& unzip plugins.zip -d plugins \
&& rm plugins.zip

ENTRYPOINT ["/sbin/entrypoint.sh"]

CMD ["app:start"]
