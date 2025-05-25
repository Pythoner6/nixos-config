# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }: rec {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = "experimental-features = nix-command flakes";
    #settings.trusted-users = ["joseph"];
    settings = {
      keep-outputs = true;
      substituters = [ "https://cosmic.cachix.org/" ];
      trusted-substituters = [ "https://nix-community.cachix.org" ];
      trusted-public-keys = [
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      #sandbox-paths = [ "/sys/fs/cgroup/" "/dev/fuse" ];
    };
  };

  system.fsPackages = [ pkgs.bindfs ];
  fileSystems = let
    mkRoSymBind = path: {
      device = path;
      fsType = "fuse.bindfs";
      options = [ "ro" "resolve-symlinks" "x-gvfs-hide" ];
    };
    aggregatedIcons = pkgs.buildEnv {
      name = "system-icons";
      paths = with pkgs; [
        gnome-themes-extra
      ];
      pathsToLink = [ "/share/icons" ];
    };
    aggregatedFonts = pkgs.buildEnv {
      name = "system-fonts";
      paths = config.fonts.packages;
      pathsToLink = [ "/share/fonts" ];
    };
  in {
    "/usr/share/icons" = mkRoSymBind "${aggregatedIcons}/share/icons";
    "/usr/local/share/fonts" = mkRoSymBind "${aggregatedFonts}/share/fonts";
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [(final: prev: {
    yubico-piv-tool = prev.yubico-piv-tool.overrideAttrs (final: prev: rec {
      version = "2.6.0-dev";
      src = pkgs.fetchFromGitHub {
        owner = "Yubico";
        repo = "yubico-piv-tool";
        #rev = "refs/tags/yubico-piv-tool-${version}";
        #rev = "b9fc20c7ab035bffbbe10f22b6e8248d0f8eac08";
        rev = "5ca7d8a69a14fe3ee0bb46a32402118831287eca";
        #rev = "b0084c3bfce307da14c49553032478ca4b8cc534";
        #hash = "sha256-53cgwXMzVKnouwHhbt6pODhjF2MH0sK5CPWpbZe71jE="; # 2.6.0
        #hash = "sha256-QCZZCr3Ou8Jyny99Z0GNFaMCHNP2ME8pZWRhU11WY9A=";
        hash = "sha256-/xgFH1HaPN5E+GjQdOIPwjXzt9BzGOmVj3cmkLHnxeI=";
        #hash = "sha256-bhTTFvW2hCH+G36kzKI8sjJRUGufc9ylP0vOXleYXus=";
      };
      patches = [
        ./0001-Add-octet-string-encoding-to-EC_POINT-for-ED25519.patch
        #./0001-No-EC_POINT-for-ed-private-keys.patch
        ./0001-Add-octet-string-type-to-create-public-key.patch
      ];
    });
    gnome = prev.gnome // {gnome-keyring = final.stdenv.mkDerivation {
      name = "modified-gnome-keyring";
      src = prev.gnome.gnome-keyring;
      nativeBuildInputs = [ final.rsync ];
      installPhase = ''
        mkdir $out
        rsync -a $src/. $out --exclude gnome-keyring-ssh.desktop
      '';
    };};
    #gnupg-patched = prev.gnupg.overrideAttrs (finalAttrs: prevAttrs: {
    #  patches = prevAttrs.patches ++ [ ./gnupg.patch ];
    #});
    strongswan = prev.strongswan.overrideAttrs (finalAttrs: prevAttrs: {
      configureFlags = prevAttrs.configureFlags ++ [ "--enable-agent" "--enable-eap-tls" ];
      patches = prevAttrs.patches ++ [ ./strongswan.patch ];
      postInstall = (prevAttrs.postInstall or "") + ''
        #cat <<EOF > $out/etc/strongswan.d/charon/pkcs11.conf 
        cat <<EOF > $out/share/strongswan/templates/config/plugins/pkcs11.conf
        pkcs11 {
          load = yes
          modules {
            ykcs11 {
              # load_certs = yes
              # os_locking = no
              path = ${final.yubico-piv-tool}/lib/libykcs11.so
            }
          }
        }
        EOF
        
        #cat <<EOF >> $out/etc/strongswan.d/charon-systemd.conf
        cat <<EOF >> $out/share/strongswan/templates/config/strongswan.d/charon-systemd.conf
        charon-systemd {
          journal {
            default = 2
          }
        }
        EOF
        
        #cat <<EOF >> $out/etc/strongswan.conf
        cat <<EOF >> $out/share/strongswan/templates/config/strongswan.conf
        charon-nm {
          load_modular = yes
          plugins {
            include strongswan.d/charon/*.conf
          }
        }
        EOF
      '';
    });
  })];

  boot.initrd = {
    systemd.enable = true;
    luks.devices = {
      nixos = {
        device = "/dev/disk/by-partuuid/19497523-4a8d-495c-b5de-976da50e31bb";
        allowDiscards = true;
        preLVM = true;
      };
    };
  };
  boot.resumeDevice = "/dev/disk/by-uuid/8fa8cb1d-cf56-4207-8315-5e0346d4682f";

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  security.tpm2.enable = true;
  security.tpm2.pkcs11.enable = true;
  security.tpm2.tctiEnvironment.enable = true;

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  #boot.binfmt.registrations.appimage = {
  #  wrapInterpreterInShell = false;
  #  interpreter = "${pkgs.appimage-run}/bin/appimage-run";
  #  recognitionType = "magic";
  #  offset = 0;
  #  mask = ''\xff\xff\xff\xff\x00\x00\x00\x00\xff\xff\xff'';
  #  magicOrExtension = ''\x7fELF....AI\x02'';
  #};

  networking.hostName = "laptop";
  networking.networkmanager = {
    enable = true;
    enableStrongSwan = true;
  };
  networking.extraHosts = ''
    10.16.3.1 gitlab.home.josephmartin.org
    10.16.3.1 registry.home.josephmartin.org
    10.16.3.2 ldap.home.josephmartin.org
    10.16.3.3 rook-ceph-rgw-objectstore.rook-system.svc
  '';
  # 127.0.0.1 events-broker-zookeeper-client.gerrit

  services.udev.packages = [
    pkgs.nitrokey-udev-rules
    pkgs.android-udev-rules
  ];

  services.automatic-timezoned.enable = true;

  services.hardware.bolt.enable = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  services.pcscd.enable = true;

  # networking.hostName = "nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  systemd.sleep.extraConfig = ''
    AllowSuspendThenHibernate=yes
    HibernateDelaySec=3600
  '';
  systemd.tmpfiles.rules = [ "d /run/tpm2-tss/eventlog 0775 root tss -" ];
  # TODO remove this when the issue is fixed on nixos-cosmic side
  systemd.user.extraConfig = ''DefaultEnvironment="PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"'';

  services.logind = {
    suspendKey = "suspend-then-hibernate";
    lidSwitch = "suspend-then-hibernate";
    lidSwitchExternalPower = "suspend-then-hibernate";
    lidSwitchDocked = "ignore";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  services.xserver.xkb.options = "terminate:ctrl_alt_bksp,caps:escape";


  # Enable the Plasma 5 Desktop Environment.
  services.displayManager.sddm.enable = false;
  services.desktopManager.plasma6.enable = false;

  #programs.ssh.askPassword = "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";
  programs.ssh.askPassword = "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";

  services.xserver.displayManager.gdm.enable = false;
  services.xserver.desktopManager.gnome.enable = false;

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.excludePackages = [ pkgs.xterm ];

  

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.drivers = with pkgs; [ gutenprint ];

  # Enable sound.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.flatpak.enable = true;

  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix-550a;

  xdg.portal = {
    enable = true;
    #extraPortals = [ pkgs.xdg-desktop-portal-kde pkgs.xdg-desktop-portal-gtk ];
  };

  users.users.joseph = {
    isNormalUser = true;
    description = "Joseph Martin";
    extraGroups = [ "networkmanager" "wheel" "tss" "docker" ];
    subUidRanges = [ { startUid = 1000000; count = 65536; } ];
    subGidRanges = [ { startGid = 1000000; count = 65536; } ];
  };
  #users.users.nixbld = {
  #  isSystemUser = true;
  #  group = "nixbld";
  #  subUidRanges = [ { startUid = 2000000; count = 65536; } ];
  #  subGidRanges = [ { startGid = 2000000; count = 65536; } ];
  #};

  environment.gnome.excludePackages = [
    pkgs.gnome-console
  ];

  environment.systemPackages = with pkgs; [
    #qemu_kvm
    #gns3-server
    #(pkgs.callPackage ./klassy.nix {})
    #sweet-nova
    #materia-kde-theme
    neovim
    libva-utils
    tpm2-tss
    tpm2-tools
    acl
    usbutils
    #plasma5Packages.plasma-thunderbolt
    #libsForQt5.qtstyleplugin-kvantum
    #kdePackages.plasma-thunderbolt
    #kdePackages.qtstyleplugin-kvantum
    #libsForQt5.polonium
    gnomeExtensions.windownavigator
    gnomeExtensions.gsconnect
    #gnomeExtensions.hibernate-status-button
    gnome-tweaks
    gnome-terminal
    yubico-piv-tool
    opensc
    yubikey-manager
    #openssl_3_1
    strongswan
    openssl
    (pkgs.stdenv.mkDerivation {
      pname = "pkcs11-provider";
      version = "git-7e1584e";
      #version = "0.5";
      #nativeBuildInputs = [ pkgs.autoconf-archive pkgs.pkg-config autoreconfHook ];
      nativeBuildInputs = [ pkg-config meson ninja ];
      #buildInputs = [ pkgs.openssl_3_1 ];
      buildInputs = [ pkgs.openssl ];
      src = pkgs.fetchFromGitHub {
        owner = "latchset";
        repo = "pkcs11-provider";
        rev = "7e1584e77f0109d23cdfa2086ea0dabd46a3992c";
        #rev = "v0.5";
        #hash = "sha256-PI4cmk/bojmn/3XaEQhU9FSzHawUYp4cmyXsjR0RG/o="; # v0.2
        #hash = "sha256-jEQYsINRZ7bi2UqOXUUmGpm+1h+1qBNe18KvfAw2JzU="; # v0.3
        #hash = "sha256-f4BbW2awSXS1srSkn1CTRCqNp+2pvVpc4YL79Ht0w0A="; # v0.4
        #hash = "sha256-ii2xQPBgqIjrAP27qTQR9IXbEGZcc79M/cYzFwcAajQ="; # v0.5
        hash = "sha256-hb+2HBKcGt/CYAFz2A6w6NBshcwK1l9GmeOUgISS9/I="; # 7e1584e77f0109d23cdfa2086ea0dabd46a3992c
      };
      patches = [
        ./0001-Add-debugging.patch
      ];
      installPhase = ''
        mkdir -p $out/lib/ossl-modules
        cp src/pkcs11.so $out/lib/ossl-modules/pkcs11.so
      '';
    })
  ];

  #environment.variables = {
  # TSS2_FAPICONF = "/etc/tpm2-tss/fapi-config.json";
  # SSH_AUTH_SOCK = "/run/user/1000/gnupg/S.gpg-agent.ssh";
  #};
  environment.sessionVariables = {
   SSH_AUTH_SOCK = "/run/user/$UID/gnupg/S.gpg-agent.ssh";
  };

  environment.etc = {
    "bash_completion.d/kubectl.bash" = {
      source = "${lib.makeSearchPath "share" [ pkgs.kubectl ] }/bash-completion/completions.kubectl.bash";
    };
    "tpm2-tss/fapi-config.json".text = ''
      {
        "ek_cert_less": "yes",
        "profile_name": "P_ECCP256SHA256",
        "profile_dir": "/etc/tpm2-tss/fapi-profiles/",
        "user_dir": "~/.local/share/tpm2-tss/user/keystore",
        "system_dir": "/var/lib/tpm2-tss/system/keystore",
        "tcti": "${lib.makeLibraryPath [pkgs.tpm2-tss ]}/libtss2-tcti-device.so:/dev/tpmrm0",
        "system_pcrs": [],
        "log_dir": "/var/run/tpm2-tss/eventlog"
      }
    '';
    "tpm2-tss/fapi-profiles/P_ECCP256SHA256.json" = {
      mode = "444";
      text = ''
        {
          "type": "TPM2_ALG_ECC",
          "nameAlg": "TPM2_ALG_SHA256",
          "srk_template": "system,restricted,decrypt,0x81000001",
          "srk_description": "Storage root key SRK",
          "srk_persistent": 0,
          "ek_template": "system,restricted,decrypt",
          "ek_description": "Endorsement key EK",
          "ecc_signing_scheme": {
            "scheme": "TPM2_ALG_ECDSA",
            "details": {
              "hashAlg": "TPM2_ALG_SHA256"
            }
          },
          "sym_mode": "TPM2_ALG_CFB",
          "sym_parameters": {
            "algorithm": "TPM2_ALG_AES",
            "keyBits": "128",
            "mode": "TPM2_ALG_CFB"
          },
          "sym_block_size": 16,
          "pcr_selection": [
            {
              "hash": "TPM2_ALG_SHA1",
              "pcrSelect": []
            },
            {
              "hash": "TPM2_ALG_SHA256",
              "pcrSelect": [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23 ]
            }
          ],
          "curveID": "TPM2_ECC_NIST_P256",
          "ek_policy": {
            "description": "Endorsement hierarchy used for policy secret.",
            "policy": [
              {
                "type": "POLICYSECRET",
                "objectName": "4000000b"
              }
            ]
          }
        }
      '';
    };
  };

  system.activationScripts.fapiDirs = lib.stringAfter [ "var" ] ''
    PATH=$PATH:${lib.makeBinPath [ pkgs.acl ]}
    mkdir -p /var/lib/tpm2-tss
    setfacl -R -m g:tss:rwx /var/lib/tpm2-tss
  '';

  virtualisation.podman.enable = true;
  virtualisation.docker = {
    enable = true;
    daemon.settings.features."containerd-snapshotter" = true;
  };
  virtualisation.libvirtd.enable = true;
  virtualisation.libvirtd.allowedBridges = [
    "virbr0"
    "virbr1"
    "virbr2"
    "virbr3"
    "virbr4"
  ];

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  # users.users.alice = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
  #   packages = with pkgs; [
  #     firefox
  #     tree
  #   ];
  # };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #   wget
  # ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  #programs.gnupg = {
  #  agent = {
  #    enable = true;
  #    enableSSHSupport = true;
  #    pinentryFlavor = "gnome3";
  #  };
  #};
  #programs.gnupg.package = pkgs.gnupg-patched;

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  networking.firewall = { 
    enable = false;
    #allowedTCPPortRanges = [ 
    #  { from = 1714; to = 1764; } # KDE Connect
    #];  
    #allowedUDPPortRanges = [ 
    #  { from = 1714; to = 1764; } # KDE Connect
    #];  
  };

  fonts = {
    packages = [
      pkgs.noto-fonts
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-emoji
    ];
    fontDir.enable = true;
    fontconfig.enable = true;
    enableDefaultPackages = true;
    fontconfig.defaultFonts = {
      emoji = [ "Noto Color Emoji" ];
      sansSerif = [ "Noto Sans CJK SC" ];
    };
  };

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}

