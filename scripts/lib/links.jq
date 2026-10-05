# Reviewed against v26.9.30 JSON and v2rayN f5747bb; see private-export.md.
def require($ok): if $ok then . else error("unsupported client schema") end;
def text_value: type=="string" and length>0 and (test("[\u0000-\u0020\u007f]")|not);
def only($allowed): (keys - $allowed | length)==0;
def node($which):
    [.outbounds[] | select(.tag==("node-"+$which))] |
    require(length==1) | .[0] |
    require(.protocol=="vless" and only(["tag","protocol","settings","streamSettings"])) |
    require(.settings | only(["vnext"])) |
    require(.settings.vnext|length==1) |
    require(.settings.vnext[0] | only(["address","port","users"])) |
    .settings.vnext[0] as $v |
    require(($v.address|text_value) and ($v.address|test("^[a-zA-Z0-9.:-]+$"))) |
    require(($v.port|type)=="number" and $v.port>=1 and $v.port<=65535 and ($v.port|floor)==$v.port) |
    require($v.users|length==1) |
    require($v.users[0] | only(["id","encryption","flow","email","level"])) |
    $v.users[0] as $u |
    require($u.id|test("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")) |
    require($u.encryption|text_value) |
    if $which=="a" then
        require(.streamSettings | only(["network","security","realitySettings"])) |
        require((.streamSettings.network=="raw" or .streamSettings.network=="tcp") and
            .streamSettings.security=="reality" and $u.flow=="xtls-rprx-vision") |
        require(.streamSettings.realitySettings |
            only(["serverName","fingerprint","password","publicKey","shortId","spiderX","mldsa65Verify"]) and
            (.serverName|text_value) and .fingerprint=="chrome" and
            ((.password // .publicKey)|text_value) and
            (.shortId|test("^([0-9a-fA-F]{2}){1,8}$")) and
            ((has("mldsa65Verify")|not) or (.mldsa65Verify|text_value)) and
            ((has("spiderX")|not) or (.spiderX|type)=="string"))
    else
        require(.streamSettings | only(["network","security","tlsSettings","xhttpSettings"])) |
        require(.streamSettings.network=="xhttp" and .streamSettings.security=="tls" and
            (($u.flow // "")=="") and ($u.encryption|startswith("mlkem768x25519plus."))) |
        require(.streamSettings.xhttpSettings |
            only(["host","path","mode"]) and .mode=="packet-up" and
            (.host|text_value) and (.path|type)=="string" and (.path|startswith("/"))) |
        require(.streamSettings.tlsSettings |
            only(["serverName","fingerprint","alpn","echConfigList"]) and
            (.serverName|text_value) and .fingerprint=="chrome" and
            (.alpn|type)=="array" and (.alpn|length)>0 and all(.alpn[];text_value) and
            ((has("echConfigList")|not) or (.echConfigList|text_value)))
    end;
def query: to_entries | map((.key|@uri)+"="+(.value|tostring|@uri)) | join("&");
def uri($o;$which):
    $o.settings.vnext[0] as $v | $v.users[0] as $u |
    (if $v.address|contains(":") then "["+$v.address+"]" else $v.address end) as $host |
    (if $which=="a" then
        $o.streamSettings.realitySettings as $r |
        {encryption:$u.encryption,flow:$u.flow,security:"reality",sni:$r.serverName,
         fp:$r.fingerprint,pbk:($r.password // $r.publicKey),sid:$r.shortId,type:"tcp"} +
        (if $r.spiderX!=null then {spx:$r.spiderX} else {} end) +
        (if $r.mldsa65Verify!=null then {pqv:$r.mldsa65Verify} else {} end)
    else
        $o.streamSettings.tlsSettings as $t | $o.streamSettings.xhttpSettings as $x |
        {encryption:$u.encryption,security:"tls",sni:$t.serverName,fp:$t.fingerprint,
         alpn:($t.alpn|join(",")),type:"xhttp",host:$x.host,path:$x.path,mode:$x.mode} +
        (if $t.echConfigList!=null then {ech:$t.echConfigList} else {} end)
    end | query) as $q |
    "vless://"+$u.id+"@"+$host+":"+($v.port|tostring)+"?"+$q+"#node-"+$which;
def full_client:
    {log:{loglevel:"warning"},
     inbounds:[
        {tag:"socks",listen:"127.0.0.1",port:10808,protocol:"socks",settings:{udp:true}},
        {tag:"http",listen:"127.0.0.1",port:10809,protocol:"http",settings:{}}],
     outbounds:[.]};
