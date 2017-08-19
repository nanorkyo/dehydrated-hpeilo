hpeilo_getconfig () {
    local domain="${1}"

    if [[ -n "${DOMAINS_D}" ]]; then
        HPEILO_CONFFILE="${DOMAINS_D}/${domain}.hpeilo_config"
    else
        HPEILO_CONFFILE="${CERTDIR}/${domain}/hpeilo_config"
    fi

    if [[ -f "${HPEILO_CONFFILE}" ]] && [[ -r "${HPEILO_CONFFILE}" ]] ; then
        . "${HPEILO_CONFFILE}"
    else
        _exiterr "${HPEILO_CONFFILE} is required."
    fi

    if [[ -z "${HPEILO_AUTHKEY:-}" ]]; then
        _exiterr "HPEILO_AUTHKEY must be set at least."
    fi
}

hpeilo_GenerateCSR () {
    local domain="${1}" csrfile="${2}" retry="30"
    hpeilo_getconfig "${domain}"

    echo -n " + Now generating HPE iLO certificate"
    curl -sk -X POST \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic ${HPEILO_AUTHKEY}" \
        -d '{"Action": "GenerateCSR", "Country": "'"${HPEILO_C}"'", "State": "'"${HPEILO_ST}"'", "City": "'"${HPEILO_L}"'", "OrgName": "'"${HPEILO_O}"'", "OrgUnit": "'"${HPEILO_OU}"'", "CommonName": "'"${domain}"'"}' \
        https://${domain}/rest/v1/Managers/1/SecurityService/HttpsCert > /dev/null

    local temp="$(_mktemp)"
    while [[ ${retry} -ne 0 ]]; do
        retry=$((retry-1))
        echo -n "."

        curl -sk -X GET \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Basic ${HPEILO_AUTHKEY}" \
            https://${domain}/rest/v1/Managers/1/SecurityService/HttpsCert | \
                get_json_string_value CertificateSigningRequest > "${temp}"

        if grep -q "BEGIN CERTIFICATE REQUEST" "${temp}" > /dev/null 2>&1; then
            echo -ne "$(cat ${temp})" > "${csrfile}"
            break
        fi

        sleep 10
    done
    rm -f "${temp}"

    echo "done"
}

hpeilo_ImportCertificate () {
    local domain="${1}" certfile="${2}"
    hpeilo_getconfig "${domain}"

    local temp="$(
        curl -sk -X POST \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -H "Authorization: Basic ${HPEILO_AUTHKEY}" \
            -d '{"Action": "ImportCertificate", "Certificate": "'"$(cat ${certfile})"'"}' \
            https://${domain}/rest/v1/Managers/1/SecurityService/HttpsCert | \
                sed -n 's/.*"MessageID": *"\([^"]*\)".*/\1/p'
    )"

    case "${temp}" in
        "iLO.0.10.ImportCertSuccessfuliLOResetinProgress")
            echo " + Certificate was successfuly imported and iLO4 rsetting..."
            ;;
        *)
            echo " + Error unkonwn status: ${temp}"
            ;;
    esac
}

hpeilo_openssl () {
    if [[ x"${1:-}${2:-}" = x"req-new" ]]; then
        shift 2
        while [ "$#" -gt 0 ]; do
            case "${1}" in
            "-out")
                hpeilo_GenerateCSR $(basename $(dirname "${2}")) "${2}"
                ;;
            *)
                ;;
            esac
            shift
        done
    else
        openssl "${@}"
    fi
}
