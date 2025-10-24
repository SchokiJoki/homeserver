# 🧱 UAS (USB Attached SCSI) unter Linux deaktivieren

## 📘 Hintergrund

UAS (USB Attached SCSI) ist ein moderner Übertragungsmodus für USB-Massenspeichergeräte, der gegenüber dem älteren „Bulk-Only Transport“ (BOT) eine bessere Leistung durch parallele Befehlsverarbeitung bietet.

Allerdings funktionieren manche USB-SATA-Adapter oder externe Festplatten **nicht korrekt mit UAS**, was zu Problemen wie folgenden führen kann:

- Laufwerk wird unregelmäßig erkannt oder getrennt  
- SMART-Daten (z. B. mit `smartctl`) sind nicht auslesbar  
- Sehr langsame Übertragungen oder Freezes  
- Docker- oder NAS-Container (z. B. Scrutiny) melden Lesefehler  

In solchen Fällen kann es helfen, **UAS gezielt für betroffene Geräte zu deaktivieren.**

---

## ⚙️ Schritt 1 – Betroffenes Gerät identifizieren

Alle USB-Geräte auflisten:

```bash
lsusb

sudo nano /etc/modprobe.d/uas-blacklist.conf

und hier
options usb_storage quirks=152d:0578:u

hinzufügen.


dann
sudo update-initramfs -u

und reboot.
