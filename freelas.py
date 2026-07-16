#!/usr/bin/env python3
"""Busca projetos na categoria Web, Mobile & Software do 99freelas
Uso: freelas.py <palavra-chave> [limite] [ordem] [--nome <filtro>]

Equivalente em Python do freelas.sh (sem depender de curl/php).
"""
import argparse
import html
import re
import sys
from datetime import datetime
from urllib.parse import quote
from urllib.request import Request, urlopen

UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36'
BASE_URL = 'https://www.99freelas.com.br/projects'
CATEGORY = 'web-mobile-e-software'

# Cores ANSI
BOLD = '\033[1m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
GREEN = '\033[0;32m'
GRAY = '\033[0;37m'
RED = '\033[0;31m'
RESET = '\033[0m'

def fetch_page(url: str) -> str:
    req = Request(url, headers={'User-Agent': UA})
    try:
        with urlopen(req) as resp:
            charset = resp.headers.get_content_charset() or 'utf-8'
            return resp.read().decode(charset, errors='replace')
    except Exception as e:
        print(f"{RED}Erro ao buscar {url}: {e}{RESET}", file=sys.stderr)
        return ''

def parse_page(content: str):
    items = []
    pattern = re.compile(r'<li class="[^"]*result-item[^"]*"[^>]*data-id="(\d+)"[^>]*data-nome="([^"]*)"[^>]*>(.*?)</li>', re.S)
    for m in pattern.finditer(content):
        item_id = m.group(1)
        title_raw = html.unescape(m.group(2))
        block = m.group(3)

        url = ''
        u = re.search(r'<h1 class="title">.*?<a href="(/project/[^"?]+)', block, re.S)
        if u:
            url = 'https://www.99freelas.com.br' + u.group(1)

        categoria = nivel = ''
        inf = re.search(r'<p class="item-text information">(.*?)</p>', block, re.S)
        if inf:
            clean = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', inf.group(1))).strip()
            parts = [p.strip() for p in clean.split('|')]
            categoria = parts[0] if parts else ''
            nivel = parts[1] if len(parts) > 1 else ''

        pub_date = ''
        pub_ts = 0
        dt = re.search(r'cp-datetime="(\d+)"', block)
        if dt:
            try:
                ts = int(dt.group(1)) // 1000
                pub_ts = ts
                pub_date = datetime.fromtimestamp(ts).strftime('%d/%m/%Y %H:%M')
            except Exception:
                pass

        proposals = 0
        p = re.search(r'Propostas:\s*<b>(\d+)</b>', block)
        if p:
            proposals = int(p.group(1))

        interessados = 0
        i = re.search(r'Interessados:\s*<b>(\d+)</b>', block)
        if i:
            interessados = int(i.group(1))

        skills = [html.unescape(s.strip()) for s in re.findall(r'<a class="habilidade">([^<]+)</a>', block)]

        desc = ''
        dm = re.search(r'class="item-text description[^"]*"[^>]*data-content="([^"]*)"', block)
        if dm:
            raw = html.unescape(dm.group(1))
            raw = re.sub(r'<br\s*/?>', ' ', raw)
            raw = re.sub(r'<[^>]+>', '', raw)
            raw = re.sub(r'\s+', ' ', raw).strip()
            desc = raw

        flags = []
        if 'flag_project_urgent' in block or 'flag_project_urgent' in block.replace('-', '_'):
            flags.append('URGENTE')
        if 'flag_project_destaque' in block:
            flags.append('DESTAQUE')
        if 'flat_project_exclusive' in block or 'flag_project_exclusive' in block:
            flags.append('EXCLUSIVO')

        items.append({
            'id': item_id,
            'title': title_raw,
            'url': url,
            'categoria': categoria,
            'nivel': nivel,
            'data': pub_date,
            'pub_ts': pub_ts,
            'propostas': proposals,
            'interessados': interessados,
            'skills': ', '.join(skills),
            'flags': ', '.join(flags),
            'desc': desc,
        })
    return items

def main():
    parser = argparse.ArgumentParser(description='Busca projetos 99freelas')
    parser.add_argument('query', nargs='?', help='palavra-chave')
    parser.add_argument('limite', nargs='?', type=int, default=0, help='limite de resultados')
    parser.add_argument('ordem', nargs='?', default='', help='ordem: propostas|propostas:desc|interessados|data:desc')
    parser.add_argument('--nome', '-n', dest='nome', default='', help='filtrar pelo texto no título')
    args = parser.parse_args()

    if not args.query and not args.nome:
        parser.print_help()
        sys.exit(1)

    query = args.query or ''
    limite = args.limite
    order = args.ordem
    filtro_nome = args.nome

    if limite > 0:
        pages = (limite + 9) // 10
    else:
        pages = 1

    query_enc = quote(query, safe='')

    all_items = []
    sep_line = '═' * 60
    print(f"{GRAY}{sep_line}{RESET}")
    order_label = f" | Ordem: {order}" if order else ''
    limite_label = f"top {limite}" if limite > 0 else 'todos os resultados'
    nome_label = f" | Filtro: \"{filtro_nome}\"" if filtro_nome else ''
    query_label = query or '(todos os projetos)'
    print(f"{GRAY}Busca: \"{query_label}\" | {limite_label}{order_label}{nome_label}{RESET}")
    print(f"{GRAY}{'─'*60}{RESET}")

    pages_fetched = 0
    for page in range(1, pages + 1):
        fetch_url = f"{BASE_URL}?q={query_enc}&category={CATEGORY}&page={page}"
        html_text = fetch_page(fetch_url)
        if not html_text:
            continue
        pages_fetched += 1
        items = parse_page(html_text)
        all_items.extend(items)

    if pages_fetched == 0:
        print(f"{RED}Nenhuma página foi buscada com sucesso. Verifique sua conexão ou tente mais tarde.{RESET}", file=sys.stderr)
        sys.exit(1)

    # Ordenação
    if order:
        parts = order.split(':')
        field = parts[0].lower()
        desc = len(parts) > 1 and parts[1].lower() == 'desc'
        key = 'pub_ts' if field == 'data' else field
        if field in ('propostas', 'interessados', 'data'):
            all_items.sort(key=lambda it: it.get(key, 0) or 0, reverse=desc)

    # Filtro por nome
    if filtro_nome:
        f = filtro_nome.lower()
        all_items = [it for it in all_items if f in it['title'].lower()]

    if limite > 0:
        all_items = all_items[:limite]

    SEP = '─' * 60
    total = len(all_items)
    for item in all_items:
        if item['flags']:
            print(f"{YELLOW}[{item['flags']}] {RESET}")
        print(f"{BOLD}{CYAN}#{item['id']} — {item['title']}{RESET}")
        print(f"{GRAY}{item['categoria']} | {item['nivel']} | {item['data']} | Propostas: {item['propostas']} | Interessados: {item['interessados']}{RESET}")
        if item['skills']:
            print(f"{GRAY}Skills: {item['skills']}{RESET}")
        if item['desc']:
            print(item['desc'])
        if item['url']:
            print(f"{CYAN}{item['url']}{RESET}")
        print(f"{GRAY}{SEP}{RESET}")

    print(f"{GRAY}{sep_line}{RESET}")

if __name__ == '__main__':
    main()
