{
  disko.devices.disk = {
    main = {
      device = "/dev/disk/by-id/nvme-eui.5cd2e47911b0139e";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
            priority = 1;
          };
          ESP = {
            type = "EF00";
            size = "1G";
            priority = 2;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          nixos = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = ["noatime"];
              extraArgs = ["-L" "nixos"];
            };
          };
        };
      };
    };
    swap = {
      device = "/dev/disk/by-id/nvme-eui.5cd2e475228a0100";
      type = "disk";
      content = {
        type = "gpt";
        partitions.swap = {
          size = "100%";
          content = {
            type = "swap";
            mountOptions = ["noatime" "nofail"];
          };
        };
      };
    };
  };
}
