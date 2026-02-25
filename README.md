# Jarbas Enterprise CLI

CLI corporativa para automação de build, deploy e gerenciamento do JBoss/WildFly.

Projetado para ambientes corporativos com foco em:

* 🔹 Automação de build Maven
* 🔹 Deploy automatizado
* 🔹 Start / Stop / Restart do JBoss
* 🔹 Monitoramento por porta
* 🔹 Logging estruturado
* 🔹 Experiência CLI profissional

---

## 📦 Requisitos

* Windows
* PowerShell 5.1+
* Java configurado
* Maven Wrapper (`mvnw.cmd`)
* JBoss / WildFly instalado
* Arquivo `jarbas.config.json`

---

## 🚀 Instalação

### 1️⃣ Clonar / Copiar o projeto

Coloque os arquivos:

```
jarbas.ps1
jarbas.config.json
```

Em uma pasta dedicada (ex: `D:\Projetos\automatizacao`).

---

### 2️⃣ Permitir execução de scripts (se necessário)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

### 3️⃣ Criar alias opcional

No seu PowerShell profile:

```powershell
Set-Alias jarbas D:\Projetos\automatizacao\jarbas.ps1
```

Agora você pode usar:

```
jarbas start
```

---

## ⚙️ Configuração

Exemplo de `jarbas.config.json`:

```json
{
  "java": {
    "home": "C:\\Java\\jdk-21",
    "bin_dir": "C:\\Java\\jdk-21\\bin"
  },
  "maven": {
    "wrapper": "D:\\Projetos\\app\\mvnw.cmd",
    "profiles": ["dev"]
  },
  "project": {
    "root_dir": "D:\\Projetos\\app",
    "target_dir": "D:\\Projetos\\app\\target",
    "artifact_name": "myapp",
    "artifact_version": "1.0.0",
    "packaging": "war"
  },
  "jboss": {
    "bin_dir": "C:\\jboss\\bin",
    "startup_script": "standalone.bat",
    "config": "standalone.xml",
    "deployments_dir": "C:\\jboss\\standalone\\deployments",
    "host": "127.0.0.1",
    "port": 9990,
    "startup_timeout": 60
  },
  "log": {
    "file": "D:\\Projetos\\automatizacao\\jarbas.log",
    "level": "INFO",
    "max_size_mb": 5
  }
}
```

---

## 📘 Comandos Disponíveis

### ▶️ start

Inicia o JBoss e aguarda a porta de management ficar online.

```
jarbas start
```

---

### ⏹ stop

Envia comando `:shutdown` via CLI e aguarda o servidor desligar.

```
jarbas stop
```

---

### 🔁 restart

Executa stop seguido de start.

```
jarbas restart
```

---

### 📦 deploy

Executa:

```
mvn clean package
```

E copia o artefato gerado para a pasta `deployments`.

```
jarbas deploy
```

Opções:

```
jarbas deploy -SkipTest
jarbas deploy -DryRun
```

---

### 🚀 start-deploy

Executa deploy e em seguida inicia o servidor.

```
jarbas start-deploy
```

---

### 📊 status

Mostra status atual:

* ONLINE / OFFLINE
* PID
* Porta

```
jarbas status
```

---

### ❓ help

Mostra ajuda geral.

```
jarbas help
```

Ou ajuda específica:

```
jarbas help start
```

---

## 🧠 Como Funciona

* O script usa `TcpClient` para validar porta aberta
* PID é armazenado em `jarbas.pid`
* Logging é gravado em arquivo configurável
* Deploy é feito copiando o artefato para `deployments`
* Shutdown é feito via `jboss-cli.bat`

---

## 🏗 Estrutura do Projeto

```
.
├── jarbas.ps1
├── jarbas.config.json
├── jarbas.log
└── jarbas.pid
```

---

## 🛠 Recursos Técnicos

* CmdletBinding nativo
* ValidateSet para comandos
* Help interativo
* Banner ASCII UTF-8
* Monitoramento de porta TCP
* Execução silenciosa do JBoss
* Timeout configurável

---

## 🔒 Boas Práticas

* Sempre use `127.0.0.1` ao invés de `localhost`
* Salve o `.ps1` como UTF-8 with BOM
* Configure corretamente o `JAVA_HOME`
* Use `-DryRun` antes de deploy em produção

---

## 📈 Roadmap Futuro

* Autocomplete PowerShell
* Estrutura modular (subcommands)
* Build para EXE
* Health-check HTTP
* Suporte multi-ambiente (dev/hml/prod)
* Integração CI/CD

---

## 📄 Licença

Uso interno corporativo.