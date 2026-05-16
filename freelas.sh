#!/bin/bash
## Busca projetos na categoria Web, Mobile & Software do 99freelas
## Uso: ./freelas.sh <palavra-chave> [limite] [ordem]
##
## Opções de ordem:
##   propostas      — nº de propostas (crescente)
##   propostas:desc — nº de propostas (decrescente)
##   interessados   — nº de interessados (crescente)
##   interessados:desc
##   data           — data de publicação (mais antiga primeiro)
##   

##./freelas.sh <keyword> [limite] [ordem]

##./freelas.sh php           # 10 resultados (1 página)
##./freelas.sh php 5         # top 5
##./freelas.sh php 5 propostas:desc   # top 5 com mais propostas
##./freelas.sh php 20 data:desc       # 20 mais recentes (busca 2 páginas automaticamente)

UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36'
BASE_URL='https://www.99freelas.com.br/projects'
CATEGORY='web-mobile-e-software'

BOLD='\033[1m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
GRAY='\033[0;37m'
RED='\033[0;31m'
RESET='\033[0m'

# Verificação de dependências
for _cmd in curl php; do
  if ! command -v "$_cmd" &>/dev/null; then
    echo -e "${RED}Erro: '$_cmd' não encontrado. Instale-o e tente novamente.${RESET}" >&2
    exit 1
  fi
done

if [[ -z "$1" ]]; then
  echo -e "Uso: $0 <palavra-chave> [limite] [ordem]"
  echo -e "  $0 nodejs"
  echo -e "  $0 php 5"
  echo -e "  $0 php 5 propostas:desc"
  echo -e "  $0 php 10 interessados"
  echo -e "  $0 php 20 data:desc"
  exit 1
fi

QUERY="$1"

# Validação do argumento limite
if [[ -n "$2" ]] && ! [[ "$2" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Erro: o limite deve ser um número inteiro não negativo.${RESET}" >&2
  exit 1
fi

LIMITE="${2:-0}"
ORDER="${3:-}"
# Calcula quantas páginas buscar (10 resultados por página)
if [[ "$LIMITE" -gt 0 ]]; then
  PAGES=$(( (LIMITE + 9) / 10 ))
else
  PAGES=1
fi
QUERY_ENC=$(php -r 'echo rawurlencode($argv[1]);' -- "$QUERY") || {
  echo -e "${RED}Erro ao codificar a query.${RESET}" >&2
  exit 1
}

# Script PHP escrito em arquivo temporário
PYPARSER=$(mktemp /tmp/freelas_parser_XXXXXX.php) || {
  echo -e "${RED}Erro ao criar arquivo temporário.${RESET}" >&2
  exit 1
}
cat > "$PYPARSER" << 'PHPEOF'
<?php
function parse_page(string $content): array {
    $results = [];
    preg_match_all(
        '/<li class="[^"]*result-item[^"]*"[^>]*data-id="(\d+)"[^>]*data-nome="([^"]*)"[^>]*>(.*?)<\/li>/s',
        $content, $items, PREG_SET_ORDER
    );
    foreach ($items as $m) {
        $item_id = $m[1];
        $block   = $m[3];
        $title   = html_entity_decode($m[2], ENT_QUOTES | ENT_HTML5, 'UTF-8');

        $url = '';
        if (preg_match('/<h1 class="title">.*?<a href="(\/project\/[^"?]+)/s', $block, $u))
            $url = 'https://www.99freelas.com.br' . $u[1];

        $categoria = $nivel = '';
        if (preg_match('/<p class="item-text information">(.*?)<\/p>/s', $block, $inf)) {
            $clean = preg_replace('/\s+/', ' ', trim(strip_tags($inf[1])));
            $parts = array_map('trim', explode('|', $clean));
            $categoria = $parts[0] ?? '';
            $nivel     = $parts[1] ?? '';
        }

        $pub_date = ''; $pub_ts = 0;
        if (preg_match('/cp-datetime="(\d+)"/', $block, $dt)) {
            $pub_ts   = intdiv((int)$dt[1], 1000);
            $pub_date = date('d/m/Y H:i', $pub_ts);
        }

        $proposals = 0;
        if (preg_match('/Propostas:\s*<b>(\d+)<\/b>/', $block, $p)) $proposals = (int)$p[1];

        $interessados = 0;
        if (preg_match('/Interessados:\s*<b>(\d+)<\/b>/', $block, $i)) $interessados = (int)$i[1];

        preg_match_all('/<a class="habilidade">([^<]+)<\/a>/', $block, $sm);
        $skills = array_map(fn($s) => html_entity_decode($s, ENT_QUOTES | ENT_HTML5, 'UTF-8'), $sm[1]);

        $desc = '';
        if (preg_match('/class="item-text description[^"]*"[^>]*data-content="([^"]*)"/', $block, $dm)) {
            $raw  = html_entity_decode($dm[1], ENT_QUOTES | ENT_HTML5, 'UTF-8');
            $raw  = preg_replace(['/<br\s*\/?>/', '/<[^>]+>/', '/\s+/'], [' ', '', ' '], trim($raw));
            $desc = mb_strlen($raw) > 200 ? mb_substr($raw, 0, 200) . '...' : $raw;
        }

        $flags = [];
        if (str_contains($block, 'flag_project_urgent'))   $flags[] = 'URGENTE';
        if (str_contains($block, 'flag_project_destaque')) $flags[] = 'DESTAQUE';
        if (str_contains($block, 'flat_project_exclusive')) $flags[] = 'EXCLUSIVO';

        $results[] = [
            'id'          => $item_id,
            'title'       => $title,
            'url'         => $url,
            'categoria'   => $categoria,
            'nivel'       => $nivel,
            'data'        => $pub_date,
            'pub_ts'      => $pub_ts,
            'propostas'   => $proposals,
            'interessados'=> $interessados,
            'skills'      => implode(', ', $skills),
            'flags'       => implode(', ', $flags),
            'desc'        => $desc,
        ];
    }
    return $results;
}

// Lê todas as páginas separadas por "\n===\n"
$all_content = file_get_contents('php://stdin');
$pages       = explode("\n===\n", $all_content);

$all_items = [];
foreach ($pages as $page_html) {
    $all_items = array_merge($all_items, parse_page($page_html));
}

// Ordenação
$order_arg = $argv[1] ?? '';
if ($order_arg) {
    $parts      = explode(':', $order_arg);
    $field      = strtolower($parts[0]);
    $desc_order = isset($parts[1]) && strtolower($parts[1]) === 'desc';
    $sort_key   = $field === 'data' ? 'pub_ts' : $field;
    $valid      = ['propostas', 'interessados', 'data'];
    if (in_array($field, $valid, true)) {
        usort($all_items, function($a, $b) use ($sort_key, $desc_order) {
            $cmp = $a[$sort_key] <=> $b[$sort_key];
            return $desc_order ? -$cmp : $cmp;
        });
    }
}

$limite = (int)($argv[2] ?? 0);
if ($limite > 0) $all_items = array_slice($all_items, 0, $limite);

$BOLD  = "\033[1m";
$CYAN  = "\033[0;36m";
$YELLOW= "\033[1;33m";
$GRAY  = "\033[0;37m";
$BLUE  = "\033[0;34m";
$RESET = "\033[0m";
$SEP   = str_repeat('─', 60);

$total = count($all_items);
foreach ($all_items as $item) {
    if ($item['flags']) echo "{$YELLOW}[{$item['flags']}]{$RESET}\n";
    echo "{$BOLD}{$CYAN}#{$item['id']} — {$item['title']}{$RESET}\n";
    echo "{$GRAY}{$item['categoria']} | {$item['nivel']} | {$item['data']} | Propostas: {$item['propostas']} | Interessados: {$item['interessados']}{$RESET}\n";
    if ($item['skills']) echo "{$GRAY}Skills: {$item['skills']}{$RESET}\n";
    if ($item['desc'])   echo "{$item['desc']}\n";
    echo "{$BLUE}{$item['url']}{$RESET}\n";
    echo "{$GRAY}{$SEP}{$RESET}\n";
}
PHPEOF

TOTAL=0
ALL_HTML_FILE=$(mktemp /tmp/freelas_html_XXXXXX.txt) || {
  echo -e "${RED}Erro ao criar arquivo temporário.${RESET}" >&2
  rm -f "$PYPARSER"
  exit 1
}
FIRST_PAGE=1
PAGES_FETCHED=0

# Garante limpeza dos arquivos temporários em caso de saída ou interrupção
trap 'rm -f "$ALL_HTML_FILE" "$PYPARSER"' EXIT INT TERM

echo -e "${GRAY}$(printf '═%.0s' {1..60})${RESET}"
ORDER_LABEL=""
LIMITE_LABEL="todos os resultados"
[[ -n "$ORDER" ]] && ORDER_LABEL=" | Ordem: ${ORDER}"
[[ "$LIMITE" -gt 0 ]] && LIMITE_LABEL="top ${LIMITE}"
echo -e "${GRAY}Busca: \"${QUERY}\" | ${LIMITE_LABEL}${ORDER_LABEL}${RESET}"
echo -e "${GRAY}$(printf '─%.0s' {1..60})${RESET}"

# Coleta todas as páginas em arquivo temporário
for page in $(seq 1 "$PAGES"); do
  FETCH_URL="${BASE_URL}?q=${QUERY_ENC}&category=${CATEGORY}&page=${page}"
  _TMPBODY=$(mktemp /tmp/freelas_body_XXXXXX.html)
  HTTP_CODE=$(curl -s -o "$_TMPBODY" -w "%{http_code}" "$FETCH_URL" -H "User-Agent: $UA")
  CURL_EXIT=$?
  HTML=$(cat "$_TMPBODY" 2>/dev/null)
  rm -f "$_TMPBODY"

  if [[ $CURL_EXIT -ne 0 ]]; then
    echo -e "${RED}Erro de rede ao buscar página ${page} (código curl: ${CURL_EXIT}).${RESET}" >&2
    continue
  fi

  if [[ "$HTTP_CODE" -ne 200 ]]; then
    echo -e "${RED}Erro HTTP ${HTTP_CODE} ao buscar página ${page}.${RESET}" >&2
    continue
  fi

  if [[ -z "$HTML" ]]; then
    echo -e "${RED}Resposta vazia ao buscar página ${page}.${RESET}" >&2
    continue
  fi

  if [[ "$FIRST_PAGE" -eq 1 ]]; then
    echo "$HTML" > "$ALL_HTML_FILE"
    FIRST_PAGE=0
  else
    printf '\n===\n' >> "$ALL_HTML_FILE"
    echo "$HTML" >> "$ALL_HTML_FILE"
  fi
  PAGES_FETCHED=$((PAGES_FETCHED + 1))
done

if [[ $PAGES_FETCHED -eq 0 ]]; then
  echo -e "${RED}Nenhuma página foi buscada com sucesso. Verifique sua conexão ou tente mais tarde.${RESET}" >&2
  exit 1
fi

# Parse, ordenação e exibição — tudo no PHP
php "$PYPARSER" "$ORDER" "$LIMITE" < "$ALL_HTML_FILE"
PHP_EXIT=$?
if [[ $PHP_EXIT -ne 0 ]]; then
  echo -e "${RED}Erro ao processar os resultados (PHP exit: ${PHP_EXIT}).${RESET}" >&2
fi

echo -e "${GRAY}$(printf '═%.0s' {1..60})${RESET}"
