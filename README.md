# Prominence II · São Paulo

Projeto Terraform para 2–5 jogadores em Minecraft Java 1.20.1. O cliente de cada jogador deve usar **Prominence II: Hasturian Era v4.1.7**. O server pack contém 376 JARs na pasta de mods. A EC2 m7i-flex.xlarge tem 4 vCPUs e 16 GiB de RAM. O serviço inicia com heap de 4 GiB e pode usar até 9 GiB, deixando memória para o sistema e para a JVM fora do heap.

## Primeira implantação

1. Instale Terraform (1.6 ou superior da série 1.x), AWS CLI e o plugin do Session Manager. Use credenciais temporárias da conta de destino. Confira a conta com `aws sts get-caller-identity`. O operador precisa de acesso a EC2/VPC, consulta dos parâmetros públicos SSM, criação da role e do instance profile e permissão iam:PassRole para a role da instância. O acesso ao Session Manager do operador é concedido separadamente.
2. Extraia o projeto e abra um terminal na pasta que contém `main.tf`. No PowerShell, execute `Copy-Item terraform.tfvars.example terraform.tfvars`. Em Linux/macOS, use `cp terraform.tfvars.example terraform.tfvars`.
3. Substitua **todos** os exemplos. Informe o IPv4 público de saída de cada jogador em /32 e o nome e UUID com hífens de cada conta Java. Leia a [EULA do Minecraft](https://www.minecraft.net/eula) e defina `accept_minecraft_eula = true` somente se concordar.
4. Inicialize e revise o plano. Confira conta, região, volume, regras de rede e IAM. Um plano real consulta a AWS. O Terraform mantém o estado local por padrão. Proteja o estado e o plano salvo, que contêm IPs e informações dos jogadores.

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan -out=servidor.tfplan
terraform show servidor.tfplan
```

**Somente após autorizar a criação**, execute o comando abaixo. Aplicar um plano salvo inicia a criação imediatamente.

```sh
terraform apply servidor.tfplan
terraform output
```

## Primeira conexão

O término do apply indica que a EC2 foi criada. O download, a instalação de dependências e a geração inicial do mundo continuam dentro da instância. Use o comando exibido por `terraform output -raw ssm_command`. Na sessão:

```sh
sudo cloud-init status --wait
sudo systemctl status minecraft --no-pager
sudo journalctl -u minecraft -f
```

Aguarde a mensagem **Done** nos logs. Conecte o cliente ao endereço de `terraform output -raw minecraft_address`. Se a conexão falhar, confira a versão do cliente, UUID, IP de origem e `sudo ss -ltnp | grep 25565`. Se a instalação falhar, leia `/var/log/cloud-init-output.log`. Após corrigir a causa (por exemplo, falta de espaço ou indisponibilidade da CDN), reexecute `sudo bash /var/lib/cloud/instance/scripts/part-001`. O instalador usa trava e só promove a pasta temporária depois de concluir as verificações. Um servidor já instalado conserva seu mundo.

## O que será criado

- Uma VPC e uma sub-rede pública em zona de sa-east-1 que oferece o tipo escolhido. O Internet Gateway fornece saída HTTPS para SSM, repositórios e autenticação. A instância recebe IPv4 público dinâmico. O SG permite entrada TCP 25565 apenas dos /32 informados. O projeto dispensa SSH, chave de acesso à VM, NAT Gateway, balanceador e Elastic IP.
- Uma instância Linux On-Demand com AL2023 padrão x86_64 obtido do parâmetro público da AWS. IMDSv2 é obrigatório. A role da EC2 recebe AmazonSSMManagedInstanceCore. O jogo roda como usuário dedicado, e a unidade systemd restringe gravações e acesso aos metadados da instância.
- **40 GiB totais** em um único volume raiz gp3 criptografado, com sistema, mods e mundo. O volume persiste em stop/start e é retido em caso de término. O Terraform bloqueia destruição e substituição da EC2 por padrão. A atualização do parâmetro público da AMI não substitui a instância existente. Planeje atualizações do AL2023 e do Java em janela com backup.
- O serviço minecraft inicia a JVM diretamente com Corretto 17 e o launcher Fabric da versão indicada pelo pack. Mantém as pastas originais de mods, configs e datapacks. A autenticação online e a whitelist ficam ativas. RCON e query ficam desativados.

[AMI pública AL2023](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami-parameter-store.html) · [Corretto 17 no AL2023](https://docs.aws.amazon.com/corretto/latest/corretto-17-ug/amazon-linux-install.html) · [Agente SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html) · [Política IAM](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html)

## Versões e integridade

Verificação em 09/11/2026. Projeto CurseForge **466901**, server file **9455984**, publicado em 05/11/2026. A rota oficial de download redirecionou à CDN ForgeCDN. O ZIP externo contém um README e um segundo ZIP. O arquivo interno variables.txt especifica Minecraft 1.20.1, Fabric Loader 0.19.3, Fabric Installer 1.1.2 e Java 17. O script usa o launcher dessas versões, como no caminho Fabric de start.sh. No primeiro início, o launcher baixa bibliotecas e arquivos do jogo.

| Arquivo verificado | SHA-256 calculado sobre o download |
|---|---|
| Server-Pack-for-v4.1.7.zip | `b818b01520327f440b0924f16a36eea7045171a54da0a62efa48374ac678af36` |
| Launcher Fabric | `0e4e87619d281f2f31d54a208a2ee5e68395cb3f332450ff2b8f7514249997d2` |

O instalador fixa os dois endereços HTTPS e hashes. Se qualquer arquivo mudar, a instalação para. Antes de atualizar, faça snapshot, confira a nova edição do **Server Pack** e as versões internas, recalcule os hashes e teste uma cópia do mundo. Os jogadores precisam atualizar os clientes em conjunto.

[Server pack oficial](https://www.curseforge.com/minecraft/modpacks/prominence-2-hasturian-era/files/9455984) · [ZIP oficial verificado](https://mediafilez.forgecdn.net/files/9455/984/Server-Pack-for-v4.1.7.zip) · [Launcher Fabric verificado](https://meta.fabricmc.net/v2/versions/loader/1.20.1/0.19.3/1.1.2/server/jar) · [Guia do autor](https://servers.cinderstonestudios.com/create-server)

## Operação sob demanda

Para encerrar uma sessão de jogo, avise os jogadores. Dentro do SSM, execute `sudo systemctl stop minecraft`. Confira em `sudo journalctl -u minecraft -n 60` que o mundo foi salvo e a JVM encerrou. Execute `sudo systemctl poweroff`. A EC2 está configurada para entrar em estado **stopped**. Parar apenas o serviço do jogo mantém a cobrança de computação.

### Ligar com a Lambda

Com o estado do Terraform desta implantação e uma sessão AWS autorizada, abra o PowerShell na pasta do projeto e execute:

```powershell
.\automacao\servidor.ps1 start
.\automacao\servidor.ps1 status
```

A primeira chamada solicita a partida. Repita status até obter running e o endereço IPv4, que pode mudar entre sessões. Use esse endereço com a porta 25565 e aguarde **Done** no log do jogo. Quem opera pelo console AWS pode invocar a função identificada por `terraform output -raw control_function` com o evento `{"action":"start"}`. Uma tentativa de conexão pelo cliente Minecraft, sozinha, não liga uma EC2 parada.

### Desligamento após 30 minutos sem jogadores

A regra EventBridge chama a Lambda a cada cinco minutos. Com a EC2 em execução, a função solicita via SSM uma consulta local à porta do jogo. O monitor acompanha o total de jogadores, os registros de entrada e saída e o processo atual do Minecraft. A primeira leitura válida inicia a janela. Uma falha, um intervalo superior a sete minutos entre leituras ou um reinício do jogo exige nova janela. O tempo mínimo é configurável em `idle_minutes` (padrão 30). A parada ocorre na primeira sondagem elegível, tipicamente entre 30 e 35 minutos. Se ninguém conseguir entrar porque o jogo ou o SSM falhou ao iniciar, a EC2 permanece ligada e pode gerar custos.

Antes de desligar, o monitor confirma novamente a contagem zero, manda o systemd encerrar o Minecraft, verifica o resultado, sincroniza o disco e solicita poweroff. O mundo fica no EBS. A ação manual `.\automacao\servidor.ps1 stop` solicita a parada imediata do jogo mesmo com jogadores presentes. Se o serviço já estiver inativo, o controle preserva a EC2 para diagnóstico. Use o procedimento SSM acima nesse caso.

A função aceita invocações autenticadas por IAM. Conceda lambda:InvokeFunction no ARN específico apenas aos operadores autorizados a ligar **e** desligar. A Lambda só pode iniciar a EC2 do projeto e enviar seu documento SSM dedicado a essa instância. O primeiro apply da infraestrutura continua sujeito a autorização. Para atualizar uma implantação existente, use a pasta com o mesmo estado, execute init e plan e confira que a EC2 e o volume estão preservados. O plano inclui Lambda, regra e destino EventBridge, documento SSM, log e permissões IAM. Ao editar controle.py, execute `python automacao/empacotar.py` antes do plano.

Para verificar na AWS após a implantação, ligue a EC2, entre no jogo e confira que ela continua ligada com um jogador. Ao sair, acompanhe os resultados no histórico do Systems Manager Run Command até a EC2 parar. O log da Lambda registra o ID do comando enviado, e o resultado da consulta local aparece na saída do comando SSM. Com a EC2 parada, as sondagens apenas consultam o estado. As chamadas Lambda, os registros e o agendamento podem gerar cobranças adicionais conforme uso e franquias da conta.

Para trocar o IP de um jogador, edite player_cidrs e revise um novo plano. A lista players alimenta somente a instalação inicial. Para alterar membros em um mundo existente, pare o serviço via SSM, edite `/srv/minecraft/server/whitelist.json` e reinicie-o. Mudanças nos parâmetros do bootstrap pedem substituição da EC2 e são bloqueadas por prevent_destroy. Para ajustar o heap, revise a unidade na VM, use `sudo systemctl daemon-reload` e reinicie o serviço em janela de manutenção.

## Backups

A tag Backup=prominence e o output root_volume_id identificam o volume para snapshots. Os backups continuam manuais.

Para o primeiro backup consistente, desligue o servidor conforme acima e aguarde o estado stopped. Do PowerShell local:

```powershell
$id = terraform output -raw instance_id
$volume = terraform output -raw root_volume_id
aws ec2 wait instance-stopped --region sa-east-1 --instance-ids $id
$snapshot = aws ec2 create-snapshot --region sa-east-1 --volume-id $volume --description "Prominence II - mundo salvo" --query SnapshotId --output text
aws ec2 wait snapshot-completed --region sa-east-1 --snapshot-ids $snapshot
```

Para ensaiar a restauração, crie um volume a partir do snapshot na mesma zona de uma EC2 de recuperação, anexe como disco secundário e monte a partição de dados em modo somente leitura (para XFS duplicado, use ro,nouuid). Com o serviço de destino parado, recupere `/srv/minecraft/server`, ajuste o proprietário para minecraft e valide o mundo em uma instância isolada com a mesma versão. Defina retenção e teste essa recuperação antes de automatizar snapshots recorrentes. Acompanhe espaço com `df -h /srv/minecraft`.

Ao desativar o projeto definitivamente, faça e verifique o snapshot primeiro. Desative conscientemente prevent_destroy no código, revise `terraform plan -destroy` e só então prossiga com a remoção autorizada. O volume raiz retido continua faturando até sua exclusão separada. Snapshots também têm ciclo de vida próprio.

## Estimativa mensal em São Paulo

Preços públicos On-Demand em USD consultados em 09/11/2026, Linux com tenancy compartilhada. EC2 **US$ 0,30524/h**, IPv4 público associado **US$ 0,005/h**, gp3 **US$ 0,152 por GiB-mês**. Para 40 GiB provisionados durante o mês inteiro, use **US$ 6,08 + US$ 0,31024 × horas ligadas**.

| Horas ligadas no mês | Estimativa antes de créditos |
|---:|---:|
| 0 | US$ 6,08 |
| 40 | US$ 18,49 |
| 100 | US$ 37,10 |
| 730 | US$ 232,56 |

Os US$ 300 informados equivalem a aproximadamente oito meses de 100 h/mês **se** todo esse uso for elegível e os créditos permanecerem válidos. Confira saldo, validade e elegibilidade no Billing. Transferências de saída faturáveis, snapshots, impostos, câmbio e outros recursos podem elevar o total. Os valores consideram o desempenho básico do gp3. Um alerta de orçamento ajuda a acompanhar o saldo.

[Catálogo AWS de São Paulo, SKUs Y7Q35QMQ5KPM54HM e FJRJF7DYJ65UXC5J](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEC2/current/sa-east-1/index.csv) · [Preço do IPv4 público](https://aws.amazon.com/vpc/pricing/) · [Estimador AWS](https://calculator.aws/)
