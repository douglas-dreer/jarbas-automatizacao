
``` ascii
               ██╗ █████╗ ██████╗ ██████╗  █████╗ ███████╗
               ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝
               ██║███████║██████╔╝██████╔╝███████║███████╗
          ██   ██║██╔══██║██╔══██╗██╔══██╗██╔══██║╚════██║
          ╚█████╔╝██║  ██║██║  ██║██████╔╝██║  ██║███████║
          ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝
```

**Jarbas Enterprise CLI** `v1.5.0`

CLI corporativa para automação de build, deploy e gerenciamento do JBoss/WildFly.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white)
![JBoss](https://img.shields.io/badge/JBoss%2FWildFly-Suportado-CC0000?style=flat-square&logo=redhat&logoColor=white)
![Maven](https://img.shields.io/badge/Maven-Wrapper-C71A36?style=flat-square&logo=apachemaven&logoColor=white)
![License](https://img.shields.io/badge/Licença-Uso%20Interno-gray?style=flat-square)

---

## ✨ Funcionalidades

| Recurso | Descrição |
|:--|:--|
| 🔨 **Build automatizado** | Integração com Maven Wrapper (`mvnw.cmd`) |
| 📦 **Deploy & Undeploy** | Copia artefato para `deployments/` com gerenciamento de markers |
| ▶️ **Start / Stop / Restart** | Controle completo do ciclo de vida do JBoss |
| 📊 **Status em tempo real** | Monitoramento de PID, porta e estado do servidor |
| 📝 **Logging estruturado** | Logs com timestamp, nível e arquivo configurável |
| 🧪 **Dry Run** | Simule operações antes de executar |
| ❓ **Help interativo** | Ajuda contextual por comando |

---

## 📋 Pré-requisitos

- **Windows** com PowerShell 5.1+
- **Java** (JDK) configurado
- **Maven Wrapper** (`mvnw.cmd`) no projeto
- **JBoss / WildFly** instalado e configurado
- Arquivo `jarbas.config.json` na raiz do script

---

## 🚀 Início Rápido

### 1. Clone o repositório

```bash
git clone <repo-url> D:\Projetos\automatizacao
cd D:\Projetos\automatizacao
```

### 2. Permitir execução de scripts

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Configurar o `jarbas.config.json`

Crie ou edite o arquivo de configuração na raiz do projeto (veja [Configuração](#️-configuração) abaixo).

### 4. (Opcional) Criar alias global

Adicione ao seu [PowerShell Profile](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles):

```powershell
Set-Alias jarbas D:\Projetos\automatizacao\jarbas.ps1
```

Agora basta usar:

```powershell
jarbas start
```

---

## 📘 Comandos

| Comando | Descrição | Exemplo |
|:--|:--|:--|
| `start` | Inicia o JBoss e aguarda a porta de management | `jarbas start` |
| `stop` | Envia `:shutdown` via CLI e aguarda parada completa | `jarbas stop` |
| `restart` | Executa `stop` seguido de `start` | `jarbas restart` |
| `deploy` | Build Maven + copia artefato para `deployments/` | `jarbas deploy` |
| `undeploy` | Remove o artefato implantado via JBoss CLI | `jarbas undeploy` |
| `remove` | Remove o artefato e markers da pasta `deployments/` | `jarbas remove` |
| `start-deploy` | Build + deploy + start em sequência | `jarbas start-deploy` |
| `status` | Exibe PID, estado e porta do servidor | `jarbas status` |
| `help` | Mostra ajuda geral ou de um comando específico | `jarbas help deploy` |

### Flags globais

| Flag | Descrição |
|:--|:--|
| `-SkipTest` | Pula testes Maven durante o build (`-DskipTests`) |
| `-DryRun` | Simula a operação sem executar |
| `-VerboseLog` | Habilita mensagens de nível `DEBUG` |
| `-Help` | Exibe a tela de ajuda |

### Exemplos de uso

```powershell
# Build pulando testes e deploy
jarbas deploy -SkipTest

# Simular deploy sem executar
jarbas deploy -DryRun

# Build completo + iniciar servidor
jarbas start-deploy

# Ver ajuda detalhada do comando deploy
jarbas help deploy
```

---

## ⚙️ Configuração

O arquivo `jarbas.config.json` deve estar na mesma pasta do script. Estrutura completa:

```jsonc
{
  "java": {
    "home": "C:\\Java\\jdk-21",           // Caminho do JDK
    "bin_dir": "C:\\Java\\jdk-21\\bin"     // Pasta bin do JDK
  },
  "jboss": {
    "home": "C:\\jboss",                   // Raiz do JBoss/WildFly
    "bin_dir": "C:\\jboss\\bin",           // Pasta bin do servidor
    "deployments_dir": "C:\\jboss\\standalone\\deployments",
    "startup_script": "standalone.bat",    // Script de inicialização
    "config": "standalone.xml",            // Configuração do servidor
    "host": "127.0.0.1",                   // Host do management
    "port": 9990,                          // Porta do management
    "startup_timeout": 120                 // Timeout em segundos
  },
  "project": {
    "root_dir": "D:\\Projetos\\app",       // Raiz do projeto Maven
    "target_dir": "D:\\Projetos\\app\\target",
    "artifact_name": "myapp",              // Nome do artefato
    "artifact_version": "1.0.0",
    "packaging": "war"                     // war | ear | jar
  },
  "maven": {
    "wrapper": "D:\\Projetos\\app\\mvnw.cmd",
    "profiles": ["dev"]                    // Profiles Maven (futuro)
  },
  "log": {
    "file": "D:\\Projetos\\automatizacao\\logs\\jarbas.log",
    "level": "INFO",                       // INFO | DEBUG
    "max_size_mb": 5
  }
}
```

---

## 🧠 Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                  jarbas.ps1                             │
│                                                         │
│  ┌────────────────┐   ┌──────────┐   ┌───────────────┐  │
│  │  Router        │ → │ Commands │ → │  JBoss CLI /  │  │
│  │ (switch)       │   │ Functions│   │  Maven Wrapper│  │
│  └────────────────┘   └──────────┘   └───────────────┘  │
│        │              │              │                  │
│        ▼              ▼              ▼                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐          │
│  │   Help   │  │  Logger  │  │   Test-Port   │          │
│  │  System  │  │  System  │  │   (TCP Mon.)  │          │
│  └──────────┘  └──────────┘  └───────────────┘          │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
  jarbas.config.json              jarbas.log
```

**Fluxo de um deploy:**

```
jarbas deploy
  │
  ├─ 1. Carrega config (jarbas.config.json)
  ├─ 2. Configura JAVA_HOME
  ├─ 3. Executa mvnw.cmd clean package
  ├─ 4. Localiza artefato em target/
  ├─ 5. Copia para deployments/
  ├─ 6. Limpa markers antigos (.deployed, .failed, ...)
  └─ 7. Cria .dodeploy → JBoss detecta e faz o deploy
```

---

## 🏗 Estrutura do Projeto

```
automatizacao/
├── jarbas.ps1             # Script principal
├── jarbas.config.json     # Configuração do ambiente
├── .gitignore             # Regras de ignore
├── README.md              # Esta documentação
├── logs/
│   └── jarbas.log         # Log de execuções
└── projeto/               # Projeto Maven de exemplo
    └── projeto-teste/
        └── ...
```

> Arquivos temporários (`jarbas.pid`, `maven-build.log`, `wildfly*/`) são excluídos pelo `.gitignore`.

---

## 🛠 Recursos Técnicos

- **`CmdletBinding`** — suporte nativo a `-Verbose`, `-Debug`, etc.
- **`ValidateSet`** — validação de comandos no parser do PowerShell
- **`TcpClient`** — monitoramento de porta sem dependências externas
- **Banner ASCII** — renderizado em UTF-8 com cores ANSI
- **Progress bar** — feedback visual durante build e deploy
- **PID tracking** — armazenamento e limpeza de PID para controle do processo

---

## 🔒 Boas Práticas

| Prática | Motivo |
|:--|:--|
| Use `127.0.0.1` ao invés de `localhost` | Evita delay de resolução DNS e ambiguidades IPv4/IPv6 |
| Salve `.ps1` como **UTF-8 with BOM** | Garante exibição correta do banner e emojis |
| Configure corretamente o `JAVA_HOME` | O Maven Wrapper e o JBoss dependem desta variável |
| Use `-DryRun` antes de deploy em produção | Valida a operação sem efeitos colaterais |
| Mantenha o `jarbas.config.json` fora do Git | Contém caminhos específicos da sua máquina |

---