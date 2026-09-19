{
  flake.homeManagerModules.zsh =
    {
      lib,
      osConfig,
      ...
    }:
    let
      appEnabled = name: lib.attrByPath [ "programs" name "extended" "enable" ] false osConfig;

      general = {
        chx = "sudo chmod 755";
        lsblk = "lsblk -o NAME,FSTYPE,SIZE,TYPE,UUID,MOUNTPOINT";
        ducks = "du -cms * | sort -rn | head -11";
        tb = "nc termbin.com 9999";
        tmpdir = "mktmpdir";
        open = "xdg-open";
        mkdir = "mkdir -vp";
        dir = "dir --color=auto";
        vdir = "vdir --color=auto";
        tempdir = "mktemp --directory";
        mktempdir = "mktemp --directory";
        du = "du -h -c";
        cls = "clear; pwd; tree";
        cl = "clear";
        c = "clear";
        clr = "clear";
        yeet = "curl parrot.live";
        ":q" = "exit";
        q = "exit";
        psf = "ps -ef | grep --color=always";
        "_" = "sudo ";
        suod = "sudo";
        gcc = "gcc -ggdb -std=c99 -Wall -Wextra -pedantic";
        dmesg = "dmesg -H --color=always";
        # Pasted "$ cmd" lines run as typed.
        "$" = " ";
        # ua comes from the oh-my-zsh universalarchive plugin.
        archive = "ua";
        nr = "nix run nixpkgs#";
        ns = "nix shell nixpkgs#";
        np = "nix profile install nixpkgs#";
      };

      navigation = {
        gitroot = "cd-gitroot";
        groot = "cd-gitroot";
        cdr = "cd-gitroot";
        cdroot = "cd-gitroot";
        jroot = "cd-gitroot";
        jgit = "cd-gitroot";
        jro = "cd-gitroot";
        ls = "eza --group-directories-first -a";
        ll = "eza --group-directories-first -haglF --git";
        la = "eza -hagl --git --icons";
        tree = "eza --tree --level=2";
      };

      network = {
        ping = "ping -c 5";
        curl = "curl -sSJL --compressed";
        wget = "wget -c --content-disposition --show-progress";
        ip = "ip -color=auto";
        ipa = "ip a";
        iptun = "ip a show tun0";
        wifi = "nmcli dev wifi";
        ports = "sudo ss -tulnp";
        port = "sudo ss -tulnp | grep -i";
        wtfip = if appEnabled "curlie" then "curlie wtfismyip.com/json" else "curl wtfismyip.com/json";
      };

      systemd = {
        sd = "sudo systemctl";
        sds = "systemctl status";
        scs = "sudo systemctl status";
        sr = "sudo systemctl restart";
        sl = "sudo systemctl list-units --type=service";
        sll = "sudo systemctl list-units --type=service --all";
        slll = "sudo systemctl list-units --type=service --all --full";
        scu = "systemctl --user";
        sus = "systemctl --user status";
        sul = "systemctl --user list-units --type=service";
        sull = "systemctl --user list-units --type=service --all";
        sulll = "systemctl --user list-units --type=service --all --full";
      };

      editors = {
        vs = "code";
        vscode = "vs";
        "vs." = "vs .";
        "v." = "vs .";
      };

      clipboard = {
        cpy = "xsel --clipboard";
        paste = "xsel --clipboard --output";
        cpys = "xsel --clipboard --input";
        pbcopy = "xsel --clipboard --input";
        pbpaste = "xsel --clipboard --output";
      };

      # forgit loads after these and replaces ga, gd, gco and its other names (modules/shell/zsh/plugins.nix).
      git = {
        g = "git";
        ga = "git add";
        gb = "git branch --all";
        gc = "git commit";
        gd = "git diff --output-indicator-new=\" \" --output-indicator-old=\" \"";
        gfu = "git fetch upstream";
        gi = "git init";
        gl = "git log --stat";
        gm = "git merge";
        gmum = "git merge upstream/master";
        gp = "git pull";
        gu = "git push";
        gpp = "git push";
        gpf = "git push --force";
        gr = "git reset";
        gs = "git status -sb";
        gap = "git add -p";
        gbi = "git bisect";
        gca = "git commit --amend --no-edit";
        gcl = "git clone --recursive";
        gco = "git checkout";
        gcm = "git commit -m";
        gds = "gd --staged";
        gdt = "git difftool";
        gra = "git remote add";
        grb = "git rebase";
        grg = "git remote get-url";
        grl = "git remote show";
        grm = "git rm";
        grs = "git remote set-url";
        gsa = "git stash apply";
        gsl = "git stash list";
        gsp = "git stash pop";
        gss = "git stash save";
        gst = "git diff --stat --color | cat";
        giturl = "git remote show origin";
      };

      docker = {
        dk = "docker";
        di = "docker images";
        dps = "docker ps";
        dpa = "docker ps -a";
        dr = "docker run";
        drm = "docker rm";
        drmi = "docker rmi";
        drmf = "docker rm -f";
        dlf = "docker logs -f";
        ds = "docker stop";
        dst = "docker stats";
        dsto = "docker stop $(docker ps -a -q)";
        dstart = "sudo systemctl restart docker.service && systemctl status docker.service";
        dpsl = "docker ps -l";
        dexec = "docker exec";
        dlog = "docker logs";
        dip = "docker inspect --format \"{{ .NetworkSettings.IPAddress }}\"";
        dstop_all = "docker stop $(docker ps -q -f \"status=running\")";
        drm_stopped = "docker rm $(docker ps -q -f \"status=exited\")";
        drmv_stopped = "docker rm -v $(docker ps -q -f \"status=exited\")";
        drm_all = "docker rm $(docker ps -a -q)";
        drmv_all = "docker rm -v $(docker ps -a -q)";
        dprune = "docker system prune -a --volumes";
        dvls = "docker volume ls";
        dvrm_all = "docker volume rm $(docker volume ls -q)";
        dvrm_dang = "docker volume rm $(docker volume ls -q -f \"dangling=true\")";
      };

      dockerCompose = {
        dc = "docker-compose";
        dce = "docker-compose exec";
        dcl = "docker-compose logs";
        dclf = "docker-compose logs -f";
        dco = "docker-compose down";
        dcps = "docker-compose ps";
        dcu = "docker-compose up";
        dcup = "docker-compose up";
        dcupb = "docker-compose up --build";
      };

      nmap = {
        nmap = "sudo -E nmap";
        nmap_open_ports = "nmap --open";
        nmap_list_interfaces = "nmap --iflist";
        nmap_slow = "sudo nmap -sS -v -T1";
        nmap_fin = "sudo nmap -sF -v";
        nmap_full = "sudo nmap -sS -T4 -PE -PP -PS80,443 -PY -g 53 -A -p1-65535 -v";
        nmap_check_for_firewall = "sudo nmap -sA -p1-65535 -v -T4";
        nmap_ping_through_firewall = "nmap -PS -PA";
        nmap_fast = "nmap -F -T5 --version-light --top-ports 300";
        nmap_detect_versions = "sudo nmap -sV -p1-65535 -O --osscan-guess -T4 -Pn";
        nmap_check_for_vulns = "nmap --script=vuln";
        nmap_full_udp = "sudo nmap -sS -sU -T4 -A -v -PE -PS22,25,80 -PA21,23,80,443,3389";
        nmap_traceroute = "sudo nmap -sP -PE -PS22,25,80 -PA21,23,80,3389 -PU -PO --traceroute";
        nmap_full_with_scripts = "sudo nmap -sS -sU -T4 -A -v -PE -PP -PS21,22,23,25,80,113,31339 -PA80,113,443,10042 -PO --script all";
        nmap_web_safe_osscan = "sudo nmap -p 80,443 -O -v --osscan-guess --fuzzy";
        nmap_ping_scan = "nmap -n -sP";
      };

      cloudflareWarp = {
        warp = "warp-cli";
      };

      wrangler = {
        wr = "wrangler";
      };

      pnpm = {
        pp = "pnpm";
      };

      tealdeer = {
        tl = "tldr --list | fzf --preview 'tldr {} --color always' | xargs tldr";
      };

      zathura = {
        zt = "zathura";
        za = "zathura";
      };

      nsxiv = {
        sx = "nsxiv";
        sxiv = "nsxiv";
      };

      lazydocker = {
        lzd = "lazydocker";
      };

      globalAliases = {
        "..." = "../..";
        "...." = "../../..";
        "....." = "../../../..";
        "......" = "../../../../..";
      };
    in
    {
      programs.zsh = {
        shellGlobalAliases = globalAliases;
        shellAliases = lib.mkMerge [
          general
          navigation
          network
          systemd
          (lib.mkIf (appEnabled "vscode-fhs") editors)
          (lib.mkIf (appEnabled "xsel") clipboard)
          (lib.mkIf (appEnabled "git") git)
          (lib.mkIf (appEnabled "docker") docker)
          (lib.mkIf (appEnabled "docker") dockerCompose)
          (lib.mkIf (appEnabled "nmap") nmap)
          (lib.mkIf (appEnabled "cloudflare-warp") cloudflareWarp)
          (lib.mkIf (appEnabled "wrangler") wrangler)
          (lib.mkIf (appEnabled "pnpm") pnpm)
          (lib.mkIf (appEnabled "tealdeer") tealdeer)
          (lib.mkIf (appEnabled "zathura") zathura)
          (lib.mkIf (appEnabled "nsxiv") nsxiv)
          (lib.mkIf (appEnabled "lazydocker") lazydocker)
        ];
      };
    };
}
