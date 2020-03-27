#!/bin/bash
# Author: Zhang Huangbin <zhb@iredmail.org>
# Purpose: Some utility functions used by entrypoint scripts.

#
# This file is managed by iRedMail Team <support@iredmail.org> with Ansible,
# please do __NOT__ modify it manually.
#

LOG_FLAG="[iRedMail]"

LOG() {
    echo -e "\e[32m${LOG_FLAG}\e[0m $@"
}

LOGN() {
    echo -ne "\e[32m${LOG_FLAG}\e[0m $@"
}

LOG_ERROR() {
    echo -e "\e[31m${LOG_FLAG} ERROR:\e[0m $@" >&2
}

LOG_WARNING() {
    echo -e "\e[33m${LOG_FLAG} WARNING:\e[0m $@"
}

# Commands.
CMD_SED="sed -i -e"

# Command used to genrate a random string.
# Usage: password="$(${RANDOM_PASSWORD})"
RANDOM_PASSWORD='eval </dev/urandom tr -dc A-Za-z0-9 | (head -c $1 &>/dev/null || head -c 30)'

# System accounts.
SYS_USER_NGINX="nginx"
SYS_GROUP_NGINX="nginx"

#
# Nginx
#
NGINX_CONF_DIR_SITES_CONF_DIR="/etc/nginx/sites-conf.d"
NGINX_CONF_DIR_TEMPLATES="/etc/nginx/templates"

check_fqdn_hostname() {
    _host="${1}"

    echo ${_host} | grep '.\..*' &>/dev/null
    if [ X"$?" != X'0' ]; then
        LOG_ERROR "HOSTNAME is not a fully qualified domain name (FQDN)."
        LOG_ERROR "Please fix it in 'iredmail-docker.conf' first."
        exit 255
    fi
}

require_non_empty_var() {
    # Usage: require_non_empty_var <VAR_NAME> <VAR_VALUE>
    _var="$1"
    _value="$2"

    if [[ X"${_value}" == X'' ]]; then
        LOG_ERROR "Variable ${_var} can not be empty, please set it in 'iredmail-docker.conf'."
        exit 255
    fi
}

run_entrypoint() {
    # Usage: run_entrypoint <path-to-entrypoint-script> [arguments]
    _script="$1"
    shift 1
    _opts="$@"

    LOG "[Entrypoint] ${_script} ${_opts}"
    . ${_script} ${_opts}
}

create_sql_user() {
    # Usage: create_user <user> <password>
    _user="$1"
    _pw="$2"
    _dot_my_cnf="/root/.my.cnf-${_user}"

    cmd_mysql="mysql -u root"

    ${cmd_mysql} mysql -e "SELECT User FROM user WHERE User='${_user}' LIMIT 1" | grep 'User' &>/dev/null
    if [[ X"$?" != X'0' ]]; then
        ${cmd_mysql} -e "CREATE USER '${_user}'@'%';"
    fi

    # Reset password.
    #${cmd_mysql} mysql -e "UPDATE user SET Password=password('${_pw}'),authentication_string=password('${_pw}') WHERE User='${_user}';"
    ${cmd_mysql} mysql -e "ALTER USER '${_user}'@'%' IDENTIFIED BY '${_pw}';"

    cat > ${_dot_my_cnf} <<EOF
[client]
host=${SQL_SERVER_ADDRESS}
port=${SQL_SERVER_PORT}
user="${_user}"
password="${_pw}"
EOF

    chown root ${_dot_my_cnf}
    chmod 0400 ${_dot_my_cnf}
}

create_log_dir() {
    _dir="${1}"
    mkdir -p ${_dir} &>/dev/null
    chown root:root ${_dir}
}

create_log_file() {
    _file="${1}"
    touch root:root ${_file}
}

#
# Roundcube
#
create_rc_custom_conf() {
    # Usage: create_rc_custom_conf <conf-file-name>
    _conf_dir="/opt/iredmail/custom/roundcube"
    _conf="${_conf_dir}/${1}"

    [ -d ${_conf_dir} ] || mkdir -p ${_conf_dir}

    if [ ! -f ${_conf} ]; then
        touch ${_conf}
        echo '<?php' >> ${_conf}
    fi

    chown nginx:nginx ${_conf}
    chmod 0400 ${_conf}
}

#
# Nginx
#
gen_symlink_of_nginx_tmpl() {
    # Usage: gen_symlink_of_tmpl <site> <src-file-name-without-ext> <dest-file-name-without-ext>
    _site="${1}"
    _conf_dir="${NGINX_CONF_DIR_SITES_CONF_DIR}/${_site}"
    _src="${NGINX_CONF_DIR_TEMPLATES}/${2}.tmpl"
    _dest="${_conf_dir}/${3}.conf"

    if [[ ! -d ${_conf_dir} ]]; then
        mkdir -p ${_conf_dir}
        chown ${SYS_USER_NGINX}:${SYS_GROUP_NGINX} ${_conf_dir}
        chmod 0644 ${_conf_dir}
    fi

    ln -sf ${_src} ${_dest}
}

#
# Fail2ban
#
enable_fail2ban_jail() {
    _conf="${1}"
    ln -sf /etc/fail2ban/jail-available/${_conf} /etc/fail2ban/jail.d/${_conf}
}
