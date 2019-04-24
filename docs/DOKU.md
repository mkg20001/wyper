# Löschstation für Festplatten

## Hardware

 - Ein Server mit min. 1 GB RAM und hotswap-fähigen Laufwerken
 - Ein USB mit min. 4 GB Speicher
 - Ein weiterer USB mit min. 2 GB Speicher

## Software

 - Ubuntu Server 18.04 LTS
 - Wyper

## Setup USB 1

Zuerst muss ein Ubuntu 18.04 Server Image heruntergeladen werden.
Die kann man hier herunterladen: http://releases.ubuntu.com/bionic/

Dannach muss dieses auf den kleineren/langsameren USB geschrieben werden

## Installation von Ubuntu Server

Zuerst müssen beide USBs an den Server angeschlossen und die Boot-Reihenfolge entsprechend konfiguriert werden

Dannach sollte sobald ein Ubuntu-Logo zusehen ist F1 gedrückt werden. Dies öffnet die Sprach-Auswahl. Hier Deutsch wählen und datnnach den Eintrag "Ubuntu Installieren" auswählen.


Im Setup dann:

## Installation von Wyper

Folgenden Befehl eingeben:

```sh
https://raw.githubusercontent.com/mkg20001/wyper/master/prepare_machine.sh
```

## Installation v
