#!/bin/sh
set -e

update_config() {
  jq "$@" /config.json >/config.json_tmp && mv /config.json_tmp /config.json
}

is_true() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

validate_port() {
  NAME="$1"
  PORT="$2"

  case "$PORT" in
    ""|*[!0-9]*)
      echo "$NAME must be a number between 1 and 65535." >&2
      exit 1
      ;;
  esac

  if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "$NAME must be a number between 1 and 65535." >&2
    exit 1
  fi
}

apply_socks5_inbound() {
  # Remove the generated SOCKS5 inbound first so toggling env vars is idempotent.
  update_config '.inbounds = [.inbounds[] | select(.tag != "socks5-in")]'

  if ! is_true "$SOCKS5_ENABLED"; then
    echo "SOCKS5 inbound is disabled."
    return
  fi

  if [ -z "$SOCKS5_PORT" ]; then
    SOCKS5_PORT="38442"
  fi
  if [ -z "$SOCKS5_LISTEN" ]; then
    SOCKS5_LISTEN="0.0.0.0"
  fi
  if [ -z "$SOCKS5_UDP" ]; then
    SOCKS5_UDP="true"
  fi

  validate_port "SOCKS5_PORT" "$SOCKS5_PORT"

  if is_true "$SOCKS5_UDP"; then
    SOCKS5_UDP_JSON=true
  else
    SOCKS5_UDP_JSON=false
  fi

  if [ -n "$SOCKS5_USER" ] || [ -n "$SOCKS5_PASS" ]; then
    if [ -z "$SOCKS5_USER" ] || [ -z "$SOCKS5_PASS" ]; then
      echo "SOCKS5_USER and SOCKS5_PASS must be set together." >&2
      exit 1
    fi

    update_config \
      --arg listen "$SOCKS5_LISTEN" \
      --argjson port "$SOCKS5_PORT" \
      --argjson udp "$SOCKS5_UDP_JSON" \
      --arg user "$SOCKS5_USER" \
      --arg pass "$SOCKS5_PASS" \
      '.inbounds += [{
        "tag": "socks5-in",
        "listen": $listen,
        "port": $port,
        "protocol": "socks",
        "settings": {
          "auth": "password",
          "accounts": [{"user": $user, "pass": $pass}],
          "udp": $udp
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      }]'
  else
    if ! is_true "$SOCKS5_ALLOW_NO_AUTH"; then
      echo "SOCKS5 inbound requires SOCKS5_USER and SOCKS5_PASS, or set SOCKS5_ALLOW_NO_AUTH=true." >&2
      exit 1
    fi

    update_config \
      --arg listen "$SOCKS5_LISTEN" \
      --argjson port "$SOCKS5_PORT" \
      --argjson udp "$SOCKS5_UDP_JSON" \
      '.inbounds += [{
        "tag": "socks5-in",
        "listen": $listen,
        "port": $port,
        "protocol": "socks",
        "settings": {
          "auth": "noauth",
          "udp": $udp
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      }]'
  fi

  echo "SOCKS5 inbound is enabled on ${SOCKS5_LISTEN}:${SOCKS5_PORT}."
}

# Check if runtime config exists
if [ -f /config/config_runtime.json ]; then
  echo "Found existing config_runtime.json, using it."
  cp /config/config_runtime.json /config.json
else
  # No runtime config, start fresh initialization
  echo "No existing config found. Starting initialization..."
  
  IPV6=$(curl -6 -sSL --connect-timeout 3 --retry 2  ip.sb || echo "null")
  IPV4=$(curl -4 -sSL --connect-timeout 3 --retry 2  ip.sb || echo "null")
  
  # 自动生成UUID
  UUID="$(/xray uuid)"
  echo "UUID: $UUID"

  # 设置默认端口
  if [ -z "$EXTERNAL_PORT" ]; then
    echo "EXTERNAL_PORT is not set. default value 443"
    EXTERNAL_PORT="443"
  fi

  # 设置DEST默认值
  if [ -z "$DEST" ]; then
    echo "DEST is not set. default value www.apple.com:443"
    DEST="www.apple.com:443"
  fi

  # 设置SERVERNAMES默认值
  if [ -z "$SERVERNAMES" ]; then
    echo "SERVERNAMES is not set. use default value [\"www.apple.com\",\"images.apple.com\"]"
    SERVERNAMES="www.apple.com images.apple.com"
  fi

  # 自动生成密钥对
  echo "Generating new key pair"
  /xray x25519 >/key
  # 新版 xray 输出格式: PrivateKey / Password (客户端公钥) / Hash32
  PRIVATEKEY=$(cat /key | grep "PrivateKey" | awk -F ': ' '{print $2}')
  PUBLICKEY=$(cat /key | grep "Password" | awk -F ': ' '{print $2}')
  echo "Private key: $PRIVATEKEY"
  echo "Public key: $PUBLICKEY"

  # 设置默认网络类型
  NETWORK="tcp"

  # 修改配置
  update_config --arg uuid "$UUID" '.inbounds[1].settings.clients[0].id = $uuid'
  update_config --arg dest "$DEST" '.inbounds[1].streamSettings.realitySettings.dest = $dest'

  SERVERNAMES_JSON_ARRAY="$(echo "[$(echo $SERVERNAMES | awk '{for(i=1;i<=NF;i++) printf "\"%s\",", $i}' | sed 's/,$//')]")"
  update_config --argjson serverNames "$SERVERNAMES_JSON_ARRAY" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames'
  update_config --argjson serverNames "$SERVERNAMES_JSON_ARRAY" '.routing.rules[0].domain = $serverNames'

  update_config --arg privateKey "$PRIVATEKEY" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey'
  update_config --arg network "$NETWORK" '.inbounds[1].streamSettings.network = $network'

  FIRST_SERVERNAME=$(echo $SERVERNAMES | awk '{print $1}')
  # 生成配置信息
  echo -e "\033[32m" >/config/config_info.txt
  echo "IPV6: $IPV6" >>/config/config_info.txt
  echo "IPV4: $IPV4" >>/config/config_info.txt
  echo "UUID: $UUID" >>/config/config_info.txt
  echo "DEST: $DEST" >>/config/config_info.txt
  echo "PORT: $EXTERNAL_PORT" >>/config/config_info.txt
  echo "SERVERNAMES: $SERVERNAMES (任选其一)" >>/config/config_info.txt
  echo "PRIVATEKEY: $PRIVATEKEY" >>/config/config_info.txt
  echo "PUBLICKEY: $PUBLICKEY" >>/config/config_info.txt
  echo "NETWORK: $NETWORK" >>/config/config_info.txt
  if [ "$IPV4" != "null" ]; then
    SUB_IPV4="vless://$UUID@$IPV4:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#${IPV4}-Reality"
    echo "IPV4 订阅连接: $SUB_IPV4" >>/config/config_info.txt
    echo -e "IPV4 订阅二维码:\n$(echo "$SUB_IPV4" | qrencode -o - -t UTF8)" >>/config/config_info.txt
  fi
  if [ "$IPV6" != "null" ];then
    SUB_IPV6="vless://$UUID@$IPV6:$EXTERNAL_PORT?encryption=none&security=reality&type=$NETWORK&sni=$FIRST_SERVERNAME&fp=chrome&pbk=$PUBLICKEY&flow=xtls-rprx-vision#${IPV6}-Reality"
    echo "IPV6 订阅连接: $SUB_IPV6" >>/config/config_info.txt
    echo -e "IPV6 订阅二维码:\n$(echo "$SUB_IPV6" | qrencode -o - -t UTF8)" >>/config/config_info.txt
  fi

  echo -e "\033[0m" >>/config/config_info.txt
  
  # Save the generated config for persistence
  echo "Persisting configuration to /config/config_runtime.json"
  cp /config.json /config/config_runtime.json
fi

apply_socks5_inbound

if [ -f /config/config_info.txt ]; then
  cat /config/config_info.txt
fi

# 运行xray
exec /xray -config /config.json
