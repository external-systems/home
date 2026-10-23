{
  disko.devices = {
    disk = {
      main = {
        name = "main-a6955264df7748288d4100c2507d47c7";
        device = "/dev/disk/by-id/nvme-512GB_SSD_MQ22W02008419";
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
              size = "16G";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = ["noatime"];
              };
            };
          };
        };
      };
    };
  };
}
