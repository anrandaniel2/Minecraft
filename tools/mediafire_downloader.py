#!/usr/bin/env python3
"""
MediaFire downloader - tries multiple extraction methods
Based on juvenal-yescas/mediafire-dl and cloudscraper logic
"""
import argparse
import re
import sys
import os
import requests
from bs4 import BeautifulSoup

CHUNK_SIZE = 512 * 1024

def extract_download_link(contents):
    # Method 1: direct download URL pattern
    for line in contents.splitlines():
        m = re.search(r'href="(https://download\d+\.mediafire\.com[^"]+)', line)
        if m:
            return m.group(1)
        m = re.search(r'href="((http|https)://download[^"]+)', line)
        if m:
            return m.group(0).split('"')[1] if '"' in m.group(0) else m.group(1)
    # Method 2: aria-label Download file
    soup = BeautifulSoup(contents, 'html.parser')
    # Look for input with aria-label
    a = soup.find("a", {"aria-label": "Download file"})
    if a and a.get("href"):
        return a.get("href")
    # Look for class input
    a = soup.find("a", class_="input")
    if a and a.get("href") and "download" in a.get("href"):
        return a.get("href")
    # Look for div with download_link
    # Method 3: look for JS variable
    m = re.search(r'"?downloadUrl"?\s*[:=]\s*"([^"]+)"', contents)
    if m:
        return m.group(1).replace("\\/", "/")
    return None

def download(url, output, quiet=False):
    url_origin = url
    sess = requests.Session()
    sess.headers.update({
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
    })

    print(f"[+] Fetching page: {url}", file=sys.stderr)
    res = sess.get(url, stream=False, timeout=30)
    print(f"[+] Status {res.status_code}, len {len(res.text)}", file=sys.stderr)
    
    if res.status_code != 200:
        print(f"Failed to fetch page: {res.status_code}", file=sys.stderr)
        return None

    # If content-disposition present, it's already file
    if 'Content-Disposition' in res.headers:
        print("[+] Direct file response", file=sys.stderr)
        with open(output, 'wb') as f:
            f.write(res.content)
        return output

    # Try to extract link
    dl_url = extract_download_link(res.text)
    if not dl_url:
        # Save page for debug
        with open("/tmp/mf_debug.html", "w", encoding="utf-8", errors="ignore") as f:
            f.write(res.text)
        print("[!] Could not extract download link, saved to /tmp/mf_debug.html", file=sys.stderr)
        print(res.text[:2000], file=sys.stderr)
        return None

    print(f"[+] Found download link: {dl_url}", file=sys.stderr)

    # Unescape
    dl_url = dl_url.replace("&amp;", "&")

    # Now download file
    print(f"[+] Downloading file from {dl_url}", file=sys.stderr)
    r = sess.get(dl_url, stream=True, timeout=60)
    total = r.headers.get('Content-Length')
    if total:
        total = int(total)
        print(f"[+] File size: {total} bytes", file=sys.stderr)

    with open(output, 'wb') as f:
        downloaded = 0
        for chunk in r.iter_content(chunk_size=CHUNK_SIZE):
            if chunk:
                f.write(chunk)
                downloaded += len(chunk)
                if not quiet and total:
                    pct = downloaded * 100 // total
                    if downloaded % (10*1024*1024) < CHUNK_SIZE:
                        print(f"  {downloaded}/{total} ({pct}%)", file=sys.stderr)

    print(f"[+] Saved to {output} ({os.path.getsize(output)} bytes)", file=sys.stderr)
    return output

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("-o", "--output", default="eaglercraft.html")
    args = parser.parse_args()
    result = download(args.url, args.output)
    sys.exit(0 if result else 1)
