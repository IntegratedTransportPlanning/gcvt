function encode(r) {
    var str = "";
    for (a in r.args) {
        str += "&" + a + "=" + r.args[a]
    }
    return encodeURIComponent(str);
}
