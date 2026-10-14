# Uppgift V42 - Compute och kom igång

**Repo:** https://github.com/80idralt/aws/tree/master/v42

**Namn:** Idris Altun

**Klass:** MOV25

**Datum:** 2026-10-14

## Syfte

Novatrix AB vill flytta sin webbplats till AWS. Den här veckan tar jag första steget. Jag startar en virtuell server i EC2, installerar en webbserver på den och lägger upp en enkel sida om Novatrix som går att nå från internet. Jag sätter också upp en budget med larm, så att jag får ett mejl innan kostnaderna drar iväg. Servern är början på den WordPress-lösning som byggs ut under resten av kursen.

## Delmoment 1: Kursrepo på GitHub

Jag skapade det publika repot `80idralt/aws` med en mapp per vecka. I mappen `v42` finns den här dokumentationen, filen `index.html` med Novatrix-sidan (samma fil som ligger på servern) och mappen `bilder` med skärmbilderna.

Nyckelfilen `novatrix-key.pem` ligger inte i repot. Den ligger bara i `.ssh`-mappen på min egen dator, och `.gitignore` stoppar alla `*.pem` så att den inte kan committas av misstag.

Repot är publikt, så jag har suddat ut eller beskurit bort uppgifter som inte ska synas för alla i några av skärmbilderna. Det gäller mitt AWS-kontonummer, min egen IP-adress och sökvägar och användarnamn från min dator. Inget av det behövs för att förstå lösningen, och kontonumret och hem-IP:n gör det lättare för någon utomstående att rikta in sig på mitt konto eller min uppkoppling.

## Delmoment 6: Kostnadskontroll

Den här delen gjorde jag först, innan jag startade något som kostar pengar. Då är larmet redan på plats om jag skulle glömma en server igång.

I **Budgets** valde jag mallen **Monthly cost budget** och satte beloppet till 10 USD i månaden. Mallen skapar tre larm som skickas till min e-post:

| Larm | Går när |
|---|---|
| Actual cost > 85 % | Jag faktiskt har förbrukat 8,50 USD |
| Actual cost > 100 % | Jag faktiskt har förbrukat 10 USD |
| Forecasted cost > 100 % | AWS räknar ut att jag kommer att gå över 10 USD under månaden |

Prognoslarmet är det viktigaste. Det kommer redan när kostnaden är på väg uppåt, så jag hinner stänga av det som glömts igång innan pengarna är förbrukade.

E-postadressen är bekräftad (1/1 email verified).

![Budgeten i listan](bilder/01-budget-lista.png)

![Budgetens detaljer](bilder/02-budget-detaljer.png)

![De tre larmen](bilder/03-budget-larm.png)

## Delmoment 2: Starta en EC2-instans

Jag startade instansen i konsolen under **EC2 → Launch instances**, i regionen **Europe (Stockholm)**. Det är regionen närmast användarna, och jag håller mig till den hela kursen.

| Inställning | Val | Varför |
|---|---|---|
| Namn | `novatrix-web` | Namnet säger vem den tillhör och vad den gör |
| AMI | Amazon Linux 2023 (64-bit x86) | AWS egen Linux, ingår i free tier |
| Instanstyp | `t3.micro` (2 vCPU, 1 GiB minne) | Liten och billig, räcker gott för en enkel webbsida och ingår i free tier |
| Key pair | `novatrix-key` (RSA, .pem) | Nyckeln jag loggar in med via SSH |
| Security group | `novatrix-web-sg` | Brandväggen runt servern, se nedan |
| Publik IP | Auto-assign: Enable | Gör servern nåbar från internet |
| Disk | 8 GiB gp3 (standard) | Räcker för en webbserver |

### Security group

Jag öppnade bara de två portar som behövs:

| Port | Till för | Tillåts från |
|---|---|---|
| 22 (SSH) | Att logga in och administrera servern | Bara min egen IP (My IP, en enda adress `/32`) |
| 80 (HTTP) | Webbsidan | Alla (`0.0.0.0/0`) |

AWS visar en varning för regler som är öppna för `0.0.0.0/0`. För port 80 är det precis meningen, eftersom en publik webbsida ska kunna nås av alla. För SSH hade det varit en risk, så den porten är låst till min IP. Det är least privilege: öppna det som behövs och inget mer.

Utgående trafik är öppen som standard. Det behövs, eftersom servern själv måste kunna hämta paket när jag installerar webbservern.

![Reglerna i security groupen](bilder/04-sg-regler.png)

### Verifiering

Instansen fick IP-adressen `13.60.55.87`. Jag väntade tills den visade **Running** och **3/3 checks passed**. Det betyder att AWS har kontrollerat både den fysiska värden, själva instansen och disken.

![Instansen är igång](bilder/05-instans-running.png)

![Detaljer om instansen](bilder/06-instans-detaljer.png)

## Delmoment 3: Anslut via SSH och installera webbservern

### Lås nyckeln

SSH vägrar använda en nyckel som andra konton på datorn kan läsa. Därför tog jag först bort de ärvda rättigheterna och gav bara mitt eget konto läsrätt:

```powershell
cd $HOME\.ssh
icacls .\novatrix-key.pem /inheritance:r
icacls .\novatrix-key.pem /grant:r "$($env:USERNAME):R"
icacls .\novatrix-key.pem
```

Den sista raden visar att bara mitt eget Windows-konto har rätt till filen, och bara läsrätt (`R`).

### Logga in

Användaren på Amazon Linux heter alltid `ec2-user`:

```powershell
ssh -i .\novatrix-key.pem ec2-user@13.60.55.87
```

Första gången frågar SSH om serverns fingerprint, och då svarar man `yes`. Väl inne kontrollerade jag vem jag är, vilken server jag är på och hur mycket disk som finns:

```
[ec2-user@ip-172-31-34-145 ~]$ whoami
ec2-user
[ec2-user@ip-172-31-34-145 ~]$ hostname
ip-172-31-34-145.eu-north-1.compute.internal
[ec2-user@ip-172-31-34-145 ~]$ df -h
Filesystem        Size  Used Avail Use% Mounted on
/dev/nvme0n1p1    8.0G  1.6G  6.4G  20% /
...
```

![Inloggad via SSH](bilder/07-ssh-inloggad.png)

### Installera webbservern

På Amazon Linux heter Apache-webbservern `httpd`. Jag uppdaterade först paketen och installerade sedan webbservern. Flaggan `-y` svarar ja på frågorna automatiskt.

```bash
sudo yum update -y
sudo yum install httpd -y
```

Sedan startade jag den. `enable` gör att den startar igen av sig själv om servern startas om.

```bash
sudo systemctl start httpd
sudo systemctl enable httpd
sudo systemctl status httpd
```

### Verifiering

Status visar att webbservern är igång, att den startar vid omstart och att den lyssnar på port 80:

```
Loaded: loaded (/usr/lib/systemd/system/httpd.service; enabled; preset: disabled)
Active: active (running) since Wed 2026-10-14 11:18:44 UTC
...
httpd[26547]: Server configured, listening on: port 80
```

![httpd är igång](bilder/08-httpd-status.png)

När jag surfade till `http://13.60.55.87` visade Apache sin testsida. Det betyder att hela vägen fungerar: internet, security groupen, port 80 och webbservern.

![Apaches testsida innan Novatrix-sidan var på plats](bilder/09-apache-testsida.png)

## Delmoment 4: Driftsätt Novatrix-sidan

Apache visar filerna i mappen `/var/www/html`, och startsidan heter `index.html`. Jag skrev sidan direkt till den filen med `sudo bash -c 'echo "..." > /var/www/html/index.html'`, där hela HTML-koden står mellan citattecknen. Inne i HTML-koden finns inga dubbla citattecken, eftersom de skulle avsluta `echo`. Därför står till exempel `lang=sv` och `charset=utf-8` utan citattecken, vilket är tillåtet i HTML.

```bash
sudo bash -c 'echo "<!DOCTYPE html>
<html lang=sv>
<head>
<meta charset=utf-8>
...
</html>" > /var/www/html/index.html'
```

Hela sidan finns i [index.html](index.html). Det är exakt samma fil som ligger på servern. `charset=utf-8` gör att å, ä och ö visas rätt.

Jag kontrollerade på servern att filen kom på plats och att Apache skickar den:

```
[ec2-user@ip-172-31-34-145 ~]$ curl -s http://localhost | grep "<h1>"
<h1>Novatrix AB</h1>
```

## Delmoment 5: Verifiera att sidan går att nå

### I webbläsaren

Sidan visas på `http://13.60.55.87`. Det står "Inte säker" i adressfältet eftersom sidan körs på http utan certifikat. Det är väntat i den här veckan.

![Novatrix-sidan på den publika IP-adressen](bilder/10-novatrix-sidan.png)

### Från min egen dator

Testet med `curl` inne på servern visar bara att Apache svarar lokalt. Därför körde jag samma sak från min egen dator, så att anropet går ut över internet och in genom security groupen precis som för en riktig besökare:

```
PS> curl.exe -I http://13.60.55.87
HTTP/1.1 200 OK
Date: Wed, 14 Oct 2026 11:26:24 GMT
Server: Apache/2.4.69 (Amazon Linux)
Last-Modified: Wed, 14 Oct 2026 11:22:39 GMT
ETag: "462-65dcb2624e4d2"
Accept-Ranges: bytes
Content-Length: 1122
Content-Type: text/html; charset=UTF-8
```

- `200 OK` betyder att sidan nås utifrån.
- `Server: Apache/2.4.69 (Amazon Linux)` visar att det är min EC2-instans som svarar.
- `Content-Length: 1122` stämmer med storleken på `index.html`, så det är Novatrix-sidan som skickas och inte testsidan.

![curl från min dator](bilder/11-curl-utifran.png)

## Resultat

| Krav | Klart | Visas i |
|---|---|---|
| EC2-instans med Amazon Linux inom free tier | ✓ | Delmoment 2 |
| Key pair och security group | ✓ | Delmoment 2 |
| Ansluten via SSH, webbserver installerad | ✓ | Delmoment 3 |
| Novatrix-sidan nåbar på publik IP | ✓ | Delmoment 4 och 5 |
| Verifierat och dokumenterat | ✓ | Varje delmoment |
| Konfigurationen i GitHub | ✓ | `index.html` i repot |
| Budget med larm på faktisk och prognostiserad kostnad | ✓ | Delmoment 6 |
