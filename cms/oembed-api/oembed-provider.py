#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs
from html import unescape, escape
from json import dumps
from fnmatch import fnmatch

# this obviously needs changing
SCHEMA = "https://easyasgcvt123.com/map/*"

# Somewhat compliant with https://oembed.com/
# test with e.g. curl -X GET '127.0.0.1:8080/?url=https://easyasgcvt123.com/map/'
class OEmbedHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            self.send_response(200)
            self.send_header('Content-type','text/json')
            self.end_headers()
            query = parse_qs(self.path[2:])
            desired_format = query.get("format",["json"])[0]
            desired_width = int(query.get("maxwidth",["10000"])[0])
            desired_height = int(query.get("maxheight",["10000"])[0])
            desired_url = unescape(query['url'][0])
            if not fnmatch(desired_url,SCHEMA): raise KeyError("URL requested " + desired_url + " did not match " + SCHEMA)
            our_width = 100
            our_height = 100
            if ((desired_width < our_width) or (desired_height < our_height)):
                html_reply = escape("<a href=" + desired_url + ">click me</a>")
                # This is a lie but I don't think it will matter
                our_width = 0
                our_height = 0
            else:
                html_reply = escape("<iframe src=" + query['url'][0] + "></iframe>")

            if (desired_format != "json"): raise ValueError("Only JSON supported")
            response = {
                "type": "rich",
                "version": 1.0, # oEmbed version, not our own!
                "width": our_width,
                "height": our_height,
                "html": html_reply,
            };
            self.wfile.write(dumps(response).encode())

        # This is lazy. We should make our own errors.
        except KeyError as err:
            error = "Missing required query: {0}".format(err)
            self.wfile.write(bytes(error,'utf-8'))
            self.send_response(404)

        except ValueError as err:
            error = "Not implemented: {0}".format(err)
            self.wfile.write(bytes(error,'utf-8'))
            self.send_response(501)

server = HTTPServer(('127.0.0.1',8080), OEmbedHandler)
server.serve_forever()
