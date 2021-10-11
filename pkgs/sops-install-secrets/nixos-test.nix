{ makeTest ? import <nixpkgs/nixos/tests/make-test-python.nix>, pkgs ? import <nixpkgs> {} }:
{
 ssh-keys = makeTest {
   name = "sops-ssh-keys";
   machine = {
     imports = [ ../../modules/sops ];
     services.openssh.enable = true;
     services.openssh.hostKeys = [{
       type = "rsa";
       bits = 4096;
       path = ./test-assets/ssh-key;
     }];
     sops.defaultSopsFile = ./test-assets/secrets.yaml;
     sops.secrets.test_key = {};
   };

   testScript = ''
     machine.succeed("cat /run/secrets/test_key | grep -q test_value")
   '';
 } {
   inherit pkgs;
   inherit (pkgs) system;
 };

 age-keys = makeTest {
   name = "sops-age-keys";
   machine = {
     imports = [ ../../modules/sops ];
     sops = {
       age.keyFile = ./test-assets/age-keys.txt;
       defaultSopsFile = ./test-assets/secrets.yaml;
       secrets.test_key = {};
     };
   };

   testScript = ''
     machine.succeed("cat /run/secrets/test_key | grep -q test_value")
   '';
  } {
    inherit pkgs;
    inherit (pkgs) system;
  };

  age-ssh-keys = makeTest {
  name = "sops-age-ssh-keys";
  machine = {
    imports = [ ../../modules/sops ];
    services.openssh.enable = true;
    services.openssh.hostKeys = [{
      type = "ed25519";
      path = ./test-assets/ssh-ed25519-key;
    }];
    sops = {
      defaultSopsFile = ./test-assets/secrets.yaml;
      secrets.test_key = {};
      # Generate a key and append it to make sure it appending doesn't break anything
      age = {
        keyFile = "/tmp/testkey";
        generateKey = true;
      };
    };
  };

  testScript = ''
    machine.succeed("cat /run/secrets/test_key | grep -q test_value")
  '';
  } {
    inherit pkgs;
    inherit (pkgs) system;
  };

 pgp-keys = makeTest {
   name = "sops-pgp-keys";
   machine = { pkgs, lib, config, ... }: {
     imports = [
       ../../modules/sops
     ];

     users.users.someuser = {
       isSystemUser = true;
       group = "nogroup";
     };

     sops.gnupg.home = "/run/gpghome";
     sops.defaultSopsFile = ./test-assets/secrets.yaml;
     sops.secrets.test_key.owner = config.users.users.someuser.name;
     sops.secrets."nested/test/file".owner = config.users.users.someuser.name;
     sops.secrets.existing-file = {
       key = "test_key";
       path = "/run/existing-file";
     };
     # must run before sops
     system.activationScripts.gnupghome = lib.stringAfter [ "etc" ] ''
       cp -r ${./test-assets/gnupghome} /run/gpghome
       chmod -R 700 /run/gpghome

       touch /run/existing-file
     '';
     # Useful for debugging
     #environment.systemPackages = [ pkgs.gnupg pkgs.sops ];
     #environment.variables = {
     #  GNUPGHOME = "/run/gpghome";
     #  SOPS_GPG_EXEC="${pkgs.gnupg}/bin/gpg";
     #  SOPSFILE = "${./test-assets/secrets.yaml}";
     #};
  };
  testScript = ''
    def assertEqual(exp: str, act: str) -> None:
        if exp != act:
            raise Exception(f"'{exp}' != '{act}'")


    value = machine.succeed("cat /run/secrets/test_key")
    assertEqual("test_value", value)

    machine.succeed("runuser -u someuser -- cat /run/secrets/test_key >&2")
    value = machine.succeed("cat /run/secrets/nested/test/file")
    assertEqual(value, "another value")

    target = machine.succeed("readlink -f /run/existing-file")
    assertEqual("/run/secrets.d/1/existing-file", target.strip())
  '';
 } {
   inherit pkgs;
   inherit (pkgs) system;
 };

 ssh-keys-early-secrets = makeTest {
   name = "sops-ssh-keys-early-secrets";
   machine = { pkgs, lib, config, ... }: {
     imports = [ ../../modules/sops ];

     users.users.someuser = {
       isNormalUser = true;
       passwordFile = config.sops.earlySecrets.someuser-password.path;
     };

     services.openssh.enable = true;
     services.openssh.hostKeys = [{
       type = "rsa";
       bits = 4096;
       path = ./test-assets/ssh-key;
     }];

     sops.defaultSopsFile = ./test-assets/secrets.yaml;
     sops.earlySecrets.someuser-password = {};
   };

   testScript = ''
     machine.wait_for_unit("multi-user.target")
     machine.wait_for_unit("getty@tty1.service")
     machine.wait_until_tty_matches(1, "login: ")
     machine.send_chars("someuser\n")
     machine.wait_until_tty_matches(1, "Password: ")
     machine.send_chars("somepassword\n")
     machine.send_chars("touch login-ok\n")
     machine.wait_for_file("/home/someuser/login-ok")
   '';
 } {
   inherit pkgs;
   inherit (pkgs) system;
 };
}
