#!/bin/bash
## Lista issues de repositórios do GitHub
## Uso: ./gh-issues.sh <owner/repo> [limite] [lang] [label]
##
## Opções de idioma (lang):
##   EN  — exibe sem tradução (padrão)
##   BR  — traduz o body para Português BR via translate-shell
##
## label: nome de uma label do GitHub (ex: bug, enhancement, "good first issue")
##         Aceita múltiplas labels separadas por vírgula: bug,enhancement
##
## Exemplos:
##   ./gh-issues.sh symfony/symfony
##   ./gh-issues.sh symfony/symfony 20
##   ./gh-issues.sh symfony/symfony 20 BR
##   ./gh-issues.sh symfony/symfony 0 EN bug
##   ./gh-issues.sh torvalds/linux 10 BR "good first issue"
##   GITHUB_TOKEN=ghp_xxx ./gh-issues.sh owner/private-repo 10 EN enhancement

BOLD='\033[1m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
GRAY='\033[0;97m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'
##se for executado sem parâmetros exibe instruções de uso
if [[ -z "$1" ]]; then
  echo -e "Uso: $0 <owner/repo> [limite] [lang] [label]"
  echo -e "  $0 symfony/symfony"
  echo -e "  $0 symfony/symfony 20"
  echo -e "  $0 symfony/symfony 20 BR"
  echo -e "  $0 symfony/symfony 0 EN bug"
  echo -e "  $0 torvalds/linux 10 BR \"good first issue\""
  exit 1
fi
# Parâmetros
# $1 = repositório (owner/repo)
# $2 = limite de issues a exibir (0 para sem limite)
# $3 = idioma de saída: EN (padrão) ou BR
# $4 = label(s) para filtrar (ex: bug | enhancement | "good first issue" | bug,enhancement)

REPO="$1"
LIMITE="${2:-0}"
LANG_OPT="${3:-}"
LABEL="${4:-}"

# Normaliza e valida o parâmetro de idioma. Ex: BR ou EN (padrão)
LANG_OPT="${LANG_OPT^^}"
if [[ -n "$LANG_OPT" && "$LANG_OPT" != "EN" && "$LANG_OPT" != "BR" ]]; then
  echo -e "${RED}Idioma inválido: '${LANG_OPT}'. Use EN ou BR.${RESET}" >&2
  exit 1
fi
if [[ "$LANG_OPT" == "BR" ]] && ! command -v trans &>/dev/null; then
  echo -e "${RED}Erro: translate-shell não está instalado. Instale com:${RESET}" >&2
  echo -e "${YELLOW}  sudo apt install translate-shell${RESET}" >&2
  exit 1
fi

# Calcula quantas páginas buscar (100 por página, default 1 página = 100 issues)
if [[ "$LIMITE" -gt 0 ]]; then
  PAGES=$(( (LIMITE + 99) / 100 ))
else
  PAGES=1
fi
# Monta headers curl
CURL_ARGS=(-s -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
[[ -n "$TOKEN" ]] && CURL_ARGS+=(-H "Authorization: Bearer $TOKEN")

# Parser PHP embutido
PHPPARSER=$(mktemp /tmp/ghissues_parser_XXXXXX.php)
cat > "$PHPPARSER" << 'PHPEOF'
<?php
$BOLD  = "\033[1m";
$CYAN  = "\033[0;36m";
$YELLOW= "\033[1;33m";
$GRAY  = "\033[0;97m";
$BLUE  = "\033[0;34m";
$GREEN = "\033[0;32m";
$RED   = "\033[0;31m";
$RESET = "\033[0m";
$SEP   = str_repeat('─', 60);

function translateBody(string $text): string {
    if (!$text) return $text;
    $tmpfile = tempnam(sys_get_temp_dir(), 'ghtr_');
    file_put_contents($tmpfile, $text);
    $result = shell_exec('trans -brief -no-ansi -i ' . escapeshellarg($tmpfile) . ' en:pt-BR 2>/dev/null');
    @unlink($tmpfile);
    return (is_string($result) && trim($result) !== '') ? trim($result) : $text;
}
$limite  = (int)($argv[3] ?? 0);
$lang    = strtolower(trim($argv[4] ?? ''));

// Lê páginas separadas por \n===\n
$raw   = file_get_contents('php://stdin');
$pages = explode("\n===\n", $raw);

$all = [];
foreach ($pages as $page_json) {
    $page_json = trim($page_json);
    if (!$page_json) continue;
    $items = json_decode($page_json, true);
    if (!is_array($items)) continue;
    foreach ($items as $item) {
        // Ignora pull requests
        if (isset($item['pull_request'])) continue;

        $all[] = $item;
    }
}

if ($limite > 0) $all = array_slice($all, 0, $limite);

$total = count($all);
if ($total === 0) {
    echo "Nenhuma issue encontrada.\n";
    exit(0);
}

foreach ($all as $item) {
    $number    = $item['number'];
    $title     = $item['title'];
    $url       = $item['html_url'];
    $comments  = $item['comments'] ?? 0;
    $created   = date('d/m/Y', strtotime($item['created_at']));
    $author    = $item['user']['login'] ?? '';
    $assignee  = $item['assignee']['login'] ?? null;
    $state     = $item['state'] ?? 'open';

    $label_names = array_map(fn($l) => $l['name'], $item['labels'] ?? []);
    $labels_str  = $label_names ? implode(', ', $label_names) : '';

    $body = $item['body'] ?? '';
    // Remove cabeçalhos de template do GitHub (linhas em negrito de seções)
    $body = preg_replace('/\*\*[^\n*]+\*\*\s*/u', '', $body);
    $body = preg_replace('/\s+/', ' ', trim(strip_tags($body)));
    $desc = $body;
    if ($lang === 'br' && $desc) {
        $desc = translateBody($desc);
    }
    echo "{$BOLD}{$CYAN}#{$number} — {$title}{$RESET}\n";
    echo "{$GRAY}Data: {$created} | Comentários: {$comments} | Autor: {$author}";
    if ($assignee) echo " | Responsável: {$assignee}";
    echo "{$RESET}\n";
    if ($labels_str) echo "{$GRAY}Labels: {$labels_str}{$RESET}\n";
    if ($desc)       echo "{$GRAY}{$desc}{$RESET}\n";
    echo "{$BLUE}{$url}{$RESET}\n";
    echo "{$GRAY}{$SEP}{$RESET}\n";
}

// Resumo
echo "\n{$BOLD}Total: {$total} issue(s){$RESET}\n";
PHPEOF

# ─── Coleta páginas ──────────────────────────────────────────────
echo -e "${GREEN}$(printf '═%.0s' {1..60})${RESET}"
LIMITE_LABEL="todos os resultados"
LANG_LABEL=""
LABEL_LABEL=""
[[ "$LIMITE" -gt 0 ]] && LIMITE_LABEL="top ${LIMITE}"
[[ "$LANG_OPT" == "BR" ]] && LANG_LABEL=" | Tradução: PT-BR"
[[ "$LANG_OPT" == "EN" ]] && LANG_LABEL=" | Idioma: EN"
[[ -n "$LABEL" ]]         && LABEL_LABEL=" | Label: ${LABEL}"
echo -e "${GRAY}Repo: ${BOLD}${REPO}${RESET}${GRAY} | ${LIMITE_LABEL}${LANG_LABEL}${LABEL_LABEL}${RESET}"
[[ "$LANG_OPT" == "BR" ]] && echo -e "${YELLOW}Traduzindo body das issues para PT-BR via translate-shell...${RESET}"
echo -e "${GRAY}$(printf '─%.0s' {1..60})${RESET}"

ALL_JSON=$(mktemp /tmp/ghissues_json_XXXXXX.txt)
FIRST=1

for page in $(seq 1 "$PAGES"); do
  FETCH_URL="https://api.github.com/repos/${REPO}/issues?state=open&per_page=100&page=${page}"
  [[ -n "$LABEL" ]] && FETCH_URL+="&labels=${LABEL// /%20}"
  HTTP_CODE=$(curl "${CURL_ARGS[@]}" -o /tmp/ghissues_body_$$.json -w "%{http_code}" "$FETCH_URL")

  if [[ "$HTTP_CODE" == "401" ]]; then
    echo -e "${RED}Erro 401: token inválido ou não informado. Defina GITHUB_TOKEN=ghp_xxxx${RESET}" >&2
    rm -f "$ALL_JSON" "$PHPPARSER" /tmp/ghissues_body_$$.json; exit 1
  elif [[ "$HTTP_CODE" == "403" ]]; then
    echo -e "${RED}Erro 403: rate limit atingido. Use GITHUB_TOKEN para aumentar o limite.${RESET}" >&2
    rm -f "$ALL_JSON" "$PHPPARSER" /tmp/ghissues_body_$$.json; exit 1
  elif [[ "$HTTP_CODE" == "404" ]]; then
    echo -e "${RED}Erro 404: repositório '${REPO}' não encontrado.${RESET}" >&2
    rm -f "$ALL_JSON" "$PHPPARSER" /tmp/ghissues_body_$$.json; exit 1
  elif [[ "$HTTP_CODE" != "200" ]]; then
    echo -e "${RED}Erro HTTP ${HTTP_CODE} ao acessar a API do GitHub.${RESET}" >&2
    rm -f "$ALL_JSON" "$PHPPARSER" /tmp/ghissues_body_$$.json; exit 1
  fi

  if [[ "$FIRST" -eq 1 ]]; then
    cat /tmp/ghissues_body_$$.json > "$ALL_JSON"
    FIRST=0
  else
    printf '\n===\n' >> "$ALL_JSON"
    cat /tmp/ghissues_body_$$.json >> "$ALL_JSON"
  fi
  rm -f /tmp/ghissues_body_$$.json

  # Para se a página veio com menos de 100 itens (última página)
  COUNT=$(php -r 'echo count(json_decode(file_get_contents($argv[1]), true) ?? []);' -- \
    <(tail -c +1 "$ALL_JSON" | awk 'BEGIN{found=0} /===/{found++} found=='"$((page-1))"'{print}') 2>/dev/null || echo 100)
done

# ─── Parse, ordenação e exibição via PHP ─────────────────────────
php "$PHPPARSER" "$FILTRO" "$ORDER" "$LIMITE" "$LANG_OPT" < "$ALL_JSON"

rm -f "$ALL_JSON" "$PHPPARSER"
echo -e "${GRAY}$(printf '═%.0s' {1..60})${RESET}"
