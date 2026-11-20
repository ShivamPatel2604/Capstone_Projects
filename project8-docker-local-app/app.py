from http.server import HTTPServer, BaseHTTPRequestHandler

class MyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()

        html = """
        <html>
        <head><title>Project 8 - Docker App</title></head>
        <body style="font-family:Arial;text-align:center;margin-top:100px;">
            <h1>Project 8 - Docker Application</h1>
            <h2>Successfully running inside a Docker container!</h2>
            <p>Capstone Projects - Shivam Patel</p>
            <h3>Docker Deployment Successful!</h3>
        </body>
        </html>
        """
        self.wfile.write(html.encode())

server = HTTPServer(("0.0.0.0", 5000), MyHandler)
print("Application running on port 5000")
server.serve_forever()
