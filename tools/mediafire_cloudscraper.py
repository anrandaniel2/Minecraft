#!/usr/bin/env python3
"""
Cloudscraper based downloader for MediaFire
"""
import sys
import re
import os

try:
    import cloudscraper
except ImportError:
    print("cloudscraper not installed, trying requests")
    cloudscraper = None

import requests
from bs4 import BeautifulSoup

def download_with_cloudscraper(url, output_path="decompiled/eaglercraft-26.2-0.6.html"):
    if cloudscraper:
        scraper = cloudscraper.create_scraper(
            browser={'browser': 'chrome', 'platform': 'windows', 'mobile': False}
        )
    else:
        scraper = requests.Session()
        scraper.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        })

    print(f"[cloudscraper] GET {url}")
    resp = scraper.get(url, timeout=30)
    print(f"Status {resp.status_code}, len {len(resp.text)}")
    
    # Try to find download link in page
    text = resp.text
    # Look for download button
    soup = BeautifulSoup(text, 'html.parser')
    link = None
    # Common selectors
    for a in soup.find_all('a'):
        href = a.get('href', '')
        if 'download' in href and 'mediafire.com' in href:
            # Filter
            if href.startswith('https://download'):
                link = href
                break
    if not link:
        m = re.search(r'href="(https://download[^"]+)"', text)
        if m:
            link = m.group(1)

    if not link:
        print("No link found, dumping first 5000 chars:")
        print(text[:5000])
        return False

    print(f"Found link: {link}")
    link = link.replace("&amp;", "&")
    # Download
    r = scraper.get(link, stream=True, timeout=120)
    print(f"Download status {r.status_code}, headers {r.headers.get('Content-Length')}")
    with open(output_path, 'wb') as f:
        for chunk in r.iter_content(chunk_size=8192*16):
            if chunk:
                f.write(chunk)
    print(f"Saved {os.path.getsize(output_path)} bytes to {output_path}")
    return True

if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else "https://www.mediafire.com/file/vvhydlnhy7cx7ir/eaglercraft-26.2-0.6.html/file"
    out = sys.argv[2] if len(sys.argv) > 2 else "decompiled/eaglercraft-26.2-0.6.html"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    ok = download_with_cloudscraper(url, out)
    sys.exit(0 if ok else 1)
