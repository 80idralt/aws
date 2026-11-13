# MOV25 - Amazon Web Services
Kursrepo för molnkursen AWS, MOV25
Av: Idris Altun
Klass: MOV25

Repot innehåller en mapp per vecka.
Varje veckomapp har en egen README som dokumenterar veckans arbete, med syfte, steg, kommandon och resultat.

## Innehåll
- [x] [V42 - Compute och kom igång](v42/); Novatrix-sidan på en EC2-server, byggd både i konsolen och från kod
- [x] [V43 - IAM och identitet](v43/); grupper för drift och utveckling samt en kedja med två roller där servern läser S3 utan nyckel, byggt både i konsolen och från kod
- [x] [V44 - Nätverk och säkerhet](v44/); eget VPC med ett publikt och två privata subnät, NACL och security groups i flera lager samt en bastion som enda väg in med SSH, byggt både i konsolen och från kod
- [x] [V45 - Storage och databas](v45/); WordPress med databasen i RDS och filerna på en delad disk i EFS samt backup till S3 som tas bort efter 14 dagar, byggt både i konsolen och från kod
- [x] [V46 - IaC med CloudFormation](v46/); hela miljön som tre CloudFormation-stackar för nät, data och webb, byggd och riven med ett skript, med en testkopia, återskapning från en ren klon och backup som läses in i en nybyggd miljö
- [ ] [V47 - Skalbarhet och tillgänglighet](v47/)
- [ ] [V48 - Monitorering och cloud native](v48/)

## Om Novatrix

Novatrix AB är det fiktiva företaget vi bygger åt genom hela kursen.
Den röda tråden är en WordPress-sajt som växer fram vecka för vecka, från en enkel webbserver på EC2 till en skalbar, säker och centralt monitorerad lösning provisionerad som kod.
