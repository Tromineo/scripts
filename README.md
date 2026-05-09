# dev-scripts

Scripts de terminal para produtividade no dia a dia: busca de issues no GitHub com filtros por label e idioma, e consulta de projetos freelance no 99freelas direto da linha de comando.

---

## Scripts

### `githubissues.sh` — GitHub Issues no terminal

Lista as issues abertas de qualquer repositório público (ou privado com token) do GitHub, com suporte a filtro por label e tradução automática.

**Uso:**
```bash
./githubissues.sh <owner/repo> [limite] [lang] [label]
```

| Parâmetro | Descrição | Padrão |
|-----------|-----------|--------|
| `owner/repo` | Repositório no formato `dono/repo` | obrigatório |
| `limite` | Número máximo de issues a exibir (`0` = sem limite) | `0` |
| `lang` | Idioma da saída: `EN` ou `BR` (traduz via translate-shell) | `EN` |
| `label` | Filtra por label. Aceita múltiplas separadas por vírgula | — |

**Exemplos:**
```bash
./githubissues.sh symfony/symfony
./githubissues.sh symfony/symfony 20
./githubissues.sh symfony/symfony 20 BR
./githubissues.sh symfony/symfony 0 EN bug
./githubissues.sh torvalds/linux 10 BR "good first issue"
./githubissues.sh facebook/react 20 EN bug,enhancement

# Com token para repositórios privados ou maior rate limit
GITHUB_TOKEN=ghp_xxx ./githubissues.sh owner/private-repo 10 EN enhancement
```

**Dependências:**
- `curl`, `php`
- `translate-shell` — apenas se usar `lang=BR` (`sudo apt install translate-shell`)

---

### `freelas.sh` — Projetos do 99freelas no terminal

Busca projetos na categoria Web, Mobile & Software do [99freelas.com.br](https://www.99freelas.com.br), com filtros por palavra-chave, limite e ordenação.

**Uso:**
```bash
./freelas.sh <palavra-chave> [limite] [ordem]
```

| Parâmetro | Descrição | Padrão |
|-----------|-----------|--------|
| `palavra-chave` | Termo de busca | obrigatório |
| `limite` | Número máximo de resultados | `10` |
| `ordem` | Critério de ordenação (ver opções abaixo) | — |

**Opções de ordem:**

| Valor | Descrição |
|-------|-----------|
| `propostas` | Menos propostas primeiro |
| `propostas:desc` | Mais propostas primeiro |
| `interessados` | Menos interessados primeiro |
| `interessados:desc` | Mais interessados primeiro |
| `data` | Mais antigas primeiro |
| `data:desc` | Mais recentes primeiro |

**Exemplos:**
```bash
./freelas.sh php
./freelas.sh php 5
./freelas.sh php 5 propostas:desc
./freelas.sh php 20 data:desc
```

**Dependências:**
- `curl`, `php`

---

## Instalação

```bash
git clone https://github.com/<seu-usuario>/dev-scripts
cd dev-scripts
chmod +x githubissues.sh freelas.sh
```

Opcionalmente, adicione ao PATH para usar de qualquer lugar:
```bash
export PATH="$PATH:/caminho/para/dev-scripts"
```
