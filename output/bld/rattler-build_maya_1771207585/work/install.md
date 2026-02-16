# Install Maya on Linux using the RPM Package

> Source: [Autodesk Help](https://help.autodesk.com/view/MAYAUL/2026/ENU/?guid=GUID-E7E054E1-0E32-4B3C-88F9-BF820EB45BE5)

The standard way of installing Maya on Linux is with the installer. However, you can also install Maya using the RPM files included in the installation package. Superuser privileges are required.

Before installing, ensure all additional required Linux packages are installed on your system.

## 1. Change to the Packages directory

```bash
cd install/Packages
```

## 2. Install licensing RPM packages

```bash
sudo dnf install adsklicensing14.0.0.10163-0-0.x86_64.rpm
sudo dnf install adskflexnetclient-11.18.0-0.x86_64.rpm
sudo dnf install adskflexnetserverIPV6-11.19.4-1.x86_64.rpm
sudo dnf install adlmapps29-29.0.2-0.x86_64.rpm
```

## 3. Verify the licensing service is running

```bash
sudo /usr/bin/systemctl status adsklicensing
```

If the service is not running:

```bash
sudo getent group adsklic &>/dev/null || sudo groupadd adsklic
sudo id -u adsklic &>/dev/null || sudo useradd -M -r -g adsklic adsklic -d / -s /usr/bin/nologin
sudo /usr/bin/systemctl enable adsklicensing --quiet
sudo /usr/bin/systemctl start adsklicensing
```

If it still won't start, run manually and check logs:

```bash
/opt/Autodesk/AdskLicensingService --run
# Logs at: /var/opt/Autodesk/AdskLicensingService/Log/AdskLicensingService.log
```

## 4. Install Maya

```bash
sudo rpm -vhi <Maya_rpm_package> --force
```

## 5. Verify Maya registration

```bash
/opt/Autodesk/AdskLicensing/<version_number>/helper/AdskLicensingInstHelper list
```

If Maya is not listed, register it manually:

```bash
sudo /opt/Autodesk/AdskLicensing/<version_number>/helper/AdskLicensingInstHelper register \
  -pk 657Q1 -pv 2025.0.0.F -el EN_US \
  -cf /var/opt/Autodesk/Adlm/<mayaversion>/MayaConfig.pit
```

Then run the `list` command again to confirm.

## 6. Install optional components

```bash
sudo dnf install <Bifrost_rpm_package>
sudo dnf install <USD_rpm_package>
sudo dnf install <LookdevX_rpm_package>
sudo dnf install <AdobeSubstance_rpm_package>
```

For MtoA:

```bash
sudo ./unix_installer.sh
```

## 7. Start Maya

```bash
/usr/autodesk/<mayaversion>/bin/maya
```

If Maya fails with "error while loading shared library", verify all required Linux packages are installed.
