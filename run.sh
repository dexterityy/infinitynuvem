#!/bin/sh

# Color definitions
PURPLE='\033[0;35m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Configuration
HOSTNAME="VPS"
HISTORY_FILE="${HOME}/.custom_shell_history"
MAX_HISTORY=1000

# Check if not installed
if [ ! -e "/.installed" ]; then
    # Check if rootfs.tar.xz or rootfs.tar.gz exists and remove them if they do
    if [ -f "/rootfs.tar.xz" ]; then
        rm -f "/rootfs.tar.xz"
    fi
    
    if [ -f "/rootfs.tar.gz" ]; then
        rm -f "/rootfs.tar.gz"
    fi
    
    # Wipe the files we downloaded into /tmp previously
    rm -rf /tmp/sbin
    
    # Mark as installed.
    touch "/.installed"
fi

# Check if the autorun script exists
if [ ! -e "/autorun.sh" ]; then
    touch /autorun.sh
    chmod +x /autorun.sh
fi

printf "\033c"
printf "${GREEN}Inicializando seu servidor VPS (Virtual Private Server). Isso pode levar apenas alguns milésimos de segundo.${NC}\n"
sleep 1
printf "\033c"

# Logger function
log() {
    level=$1
    message=$2
    color=$3
    
    if [ -z "$color" ]; then
        color=${NC}
    fi
    
    printf "${color}[$level]${NC} $message\n"
}

# Function to handle cleanup on exit
cleanup() {
    log "Infinity Nuvem" "Sessão encerrada. Adeus!" "$GREEN"
    exit 0
}

# Function to detect the machine architecture
detect_architecture() {
    # Detect the machine architecture.
    ARCH=$(uname -m)

    # Detect architecture and return the corresponding value
    case "$ARCH" in
        x86_64)
            echo "amd64"
        ;;
        aarch64)
            echo "arm64"
        ;;
        riscv64)
            echo "riscv64"
        ;;
        *)
            log "Infinity Nuvem" "Arquitetura de CPU não suportada: $ARCH" "$RED"
        ;;
    esac
}

# Function to get formatted directory
get_formatted_dir() {
    current_dir="$PWD"
    case "$current_dir" in
        "$HOME"*)
            printf "~${current_dir#$HOME}"
        ;;
        *)
            printf "$current_dir"
        ;;
    esac
}

print_instructions() {
    log "Informação sobre IP Compartilhado" "Sua máquina não possui IP dedicado, sendo compartilhado com outros usuários. Isso não impede a execução de projetos, como hospedagem de sites, aplicações ou testes." "$YELLOW"
    log "Acesso SSH – Guia de Configuração" "Para acessar sua máquina via SSH, siga os passos abaixo:" "$YELLOW"
    log "Infinity Nuvem" "Execute: apt update && apt upgrade" "$YELLOW"
    log "Infinity Nuvem" "Após concluir, instale o Dropbear com: apt install dropbear e confirme com y" "$YELLOW"
    log "Infinity Nuvem" "Em seguida, habilite a porta desejada: dropbear -p <sua porta>" "$YELLOW"
    log "Infinity Nuvem" "Por fim, defina sua senha com: passwd e digite a senha desejada." "$YELLOW"
    log "IMPORTANTE" "Vale lembrar que é necessário ativar a porta sempre que o servidor for desligado e ligado novamente." "$RED"
    log "Infinity Nuvem" "Digite 'help' para visualizar uma lista de comandos personalizados disponíveis." "$YELLOW"
}

# Function to print prompt
print_prompt() {
    user="$1"
    printf "\n${GREEN}${user}@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}# "
}

# Function to save command to history
save_to_history() {
    cmd="$1"
    if [ -n "$cmd" ] && [ "$cmd" != "exit" ]; then
        printf "$cmd\n" >> "$HISTORY_FILE"
        # Keep only last MAX_HISTORY lines
        if [ -f "$HISTORY_FILE" ]; then
            tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
            mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
        fi
    fi
}

# Function reinstall the OS
reinstall() {
    # Source the /etc/os-release file to get OS information
    . /etc/os-release

    printf "${YELLOW}Tem certeza de que deseja reinstalar o sistema operacional? Isso apagará todos os dados. (yes/no): ${NC}"
    read -r confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Infinity Nuvem" "Reinstalação cancelada." "$YELLOW"
        return
    fi
    
    log "Infinity Nuvem" "Prosseguindo com a reinstalação..." "$GREEN"
    if [ "$ID" = "alpine" ] || [ "$ID" = "chimera" ]; then
        rm -rf / > /dev/null 2>&1
    else
        rm -rf --no-preserve-root / > /dev/null 2>&1
    fi
}

# Function to install wget
install_wget() {
    distro=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    
    case "$distro" in
        "debian"|"ubuntu"|"devuan"|"linuxmint"|"kali")
            apt-get update -qq && apt-get install -y -qq wget > /dev/null 2>&1
        ;;
        "void")
            xbps-install -Syu -q wget > /dev/null 2>&1
        ;;
        "centos"|"fedora"|"rocky"|"almalinux"|"openEuler"|"amzn"|"ol")
            yum install -y -q wget > /dev/null 2>&1
        ;;
        "opensuse"|"opensuse-tumbleweed"|"opensuse-leap")
            zypper install -y -q wget > /dev/null 2>&1
        ;;
        "alpine"|"chimera")
            apk add --no-scripts -q wget > /dev/null 2>&1
        ;;
        "gentoo")
            emerge --sync -q && emerge -q wget > /dev/null 2>&1
        ;;
        "arch")
            pacman -Syu --noconfirm --quiet wget > /dev/null 2>&1
        ;;
        "slackware")
            yes | slackpkg install wget > /dev/null 2>&1
        ;;
        *)
            log "Infinity Nuvem" "Distribuição não suportada: $distro" "$RED"
            return 1
        ;;
    esac
}

# Function to install SSH from the repository
install_ssh() {
    # Check if SSH is already installed
    if [ -f "/usr/local/bin/ssh" ]; then
        log "Infinity Nuvem" "O SSH já está instalado." "$RED"
        return 1
    fi

    # Install wget if not found
    if ! command -v wget &> /dev/null; then
        log "INFO" "Instalando o wget" "$YELLOW"
        install_wget
    fi
    
    log "Infinity Nuvem" "Instalando o SSH." "$YELLOW"
    
    # Determine the architecture
    arch=$(detect_architecture)
    
    # URL to download the SSH binary
    url="https://github.com/ysdragon/ssh/releases/latest/download/ssh-$arch"
    
    # Download the SSH binary
    wget -q -O /usr/local/bin/ssh "$url" || {
        log "Infinity Nuvem" "Falha ao baixar o SSH." "$RED"
        return 1
    }
    
    # Make the binary executable
    chmod +x /usr/local/bin/ssh || {
        log "Infinity Nuvem" "Falha ao tornar o ssh executável." "$RED"
        return 1
    }    

    log "Infinity Nuvem" "SSH instalado com sucesso." "$GREEN"
}

# Function to print initial banner
print_banner() {
    printf "\033c"  # limpa a tela
    cat << 'EOF'

==============================================================
                         INFINITY NUVEM
                     https://infinitynuvem.xyz/
==============================================================


        .--.
       |o_o |
       |:_/ |
      //   \\ \
     (|     | )
    /'\_   _/'\
    \___)=(___/
    

                O que vamos criar hoje?

==============================================================

EOF
}


# Function to print a beautiful help message
print_help_message() {
    printf "${PURPLE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┃                          ${GREEN} Infinity Nuvem ${PURPLE}                  ┃${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}clear, cls${GREEN}         ❯  Limpe a tela                                  ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}exit${GREEN}               ❯  Desligue o servidor                               ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}history${GREEN}            ❯  Mostrar histórico de comandos                              ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}reinstall${GREEN}          ❯  Reinstale o servidor                              ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}install-ssh${GREEN}        ❯  Instale nosso servidor SSH personalizado                     ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃     ${YELLOW}help${GREEN}               ❯  Exibir esta mensagem de ajuda                         ${PURPLE}┃${NC}\n"
    printf "${PURPLE}┃                                                                             ┃${NC}\n"
    printf "${PURPLE}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}\n"
}

# Function to handle command execution
execute_command() {
    cmd="$1"
    user="$2"
    
    # Save command to history
    save_to_history "$cmd"
    
    # Handle special commands
    case "$cmd" in
        "clear"|"cls")
            print_banner
            print_prompt "$user"
            return 0
        ;;
        "exit")
            cleanup
        ;;
        "history")
            if [ -f "$HISTORY_FILE" ]; then
                cat "$HISTORY_FILE"
            fi
            print_prompt "$user"
            return 0
        ;;
        "reinstall")
            log "Infinity Nuvem" "Reinstalando...." "$GREEN"
            reinstall
            exit 2
        ;;
        "sudo"*|"su"*)
            log "ERROR" "Você já está executando como root." "$RED"
            print_prompt "$user"
            return 0
        ;;
        "install-ssh")
            install_ssh
            print_prompt "$user"
            return 0
        ;;
        "help")
            print_help_message
            print_prompt "$user"
            return 0
        ;;
        *)
            eval "$cmd"
            print_prompt "$user"
            return 0
        ;;
    esac
}

# Function to run command prompt for a specific user
run_prompt() {
    user="$1"
    read -r cmd
    
    execute_command "$cmd" "$user"
    print_prompt "$user"
}

# Create history file if it doesn't exist
touch "$HISTORY_FILE"

# Set up trap for clean exit
trap cleanup INT TERM

# Print the initial banner
print_banner

# Print the initial instructions
print_instructions

# Print initial command
printf "${GREEN}root@${HOSTNAME}${NC}:${RED}$(get_formatted_dir)${NC}#\n"

# Execute autorun.sh
sh "/autorun.sh"

# Main command loop
while true; do
    run_prompt "user"
done