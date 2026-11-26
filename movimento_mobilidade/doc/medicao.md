# Medição e score

Regras aplicadas por `iniciarAvaliacao`. O protocolo de câmera de 5 posturas usa
critérios próprios, definidos em `lib/src/services/protocol_service.dart`.

Os limites abaixo são constantes no código. Ao mudar uma delas, atualize este
documento.

## Ângulos

Cada ângulo é calculado no plano da imagem, no ponto do meio, de 0° a 180°.

| Chave | Pontos usados |
| --- | --- |
| `ombro_*` | quadril, **ombro**, cotovelo |
| `quadril_*` | ombro, **quadril**, joelho |
| `joelho_*` | quadril, **joelho**, tornozelo |
| `tornozelo_*` | joelho, **tornozelo ou calcanhar**, ponta do pé |
| `coluna` | meio dos ombros, **meio dos quadris**, vertical (0° = tronco ereto) |

- Os pontos e os ângulos passam por um filtro One Euro para reduzir o tremor.
- Quando um ponto falha, o último valor válido é mantido por até 4 quadros.
- Nas vistas frontal e diagonal, quadril e joelho podem receber uma compensação
  pelo encurtamento do fêmur na imagem, e o ângulo do tornozelo é estimado pela
  elevação do calcanhar.
- No agachamento de perfil, usa-se o ângulo medido, sem essas compensações; o
  vértice do tornozelo é o ponto do tornozelo. Os pontos do lado oposto à câmera
  são descartados.

Por isso, os ângulos de quadril, joelho e tornozelo registrados na abdução
frontal são estimativas. Eles não entram no score.

## Enquadramento

| Critério | Limite |
| --- | --- |
| Pontos obrigatórios | Nariz, ombros, quadris, joelhos e tornozelos (no perfil, só o lado visível), com confiança mínima de 0,25 |
| Bordas | Margem de 2% da área da câmera |
| Altura estimada do corpo | De 42% a 92% da área |
| Desvio horizontal do centro | Até 20% da largura |
| Rotação do corpo, de frente | Até 38° |
| Rotação do corpo, de perfil | Pelo menos 48°, com o lado direito para a câmera |

Quem já está enquadrado ganha uma folga, para o aviso não oscilar.

| Tempo | Valor |
| --- | --- |
| Persistência antes de tratar uma saída como problema (para o aviso) | 0,35 s |
| Corpo enquadrado antes de começar a contar | 1,5 s |
| Saída tolerada durante a captura | 0,8 s; depois disso, a repetição em curso é cancelada |
| Intervalo entre avisos de problemas diferentes | 3 s |
| Repetição do mesmo aviso | 10 s |

Os avisos de enquadramento são falados, com destaque vermelho sobre a câmera e
vibração leve quando o problema muda. Falhas de voz não interrompem a avaliação.

## Contagem de repetições

A contagem usa histerese sobre um ângulo de referência.

| Movimento | Referência | Entra no pico | Conclui ao voltar |
| --- | --- | --- | --- |
| Abdução | Média dos dois ombros | 70° ou mais | 45° ou menos |
| Agachamento | Joelho direito | 130° ou menos | 155° ou mais |

- Cada movimento termina com 3 repetições.
- Ciclos com menos de 0,5 s são ignorados.
- Os ângulos de todas as articulações são guardados no instante do pico da
  referência. O pico de cada articulação pode ocorrer em outro instante.
- A posição inicial (`restAngles`) é a mediana de até 30 quadros recentes em
  repouso.
- `rom_min` e `rom_max` cobrem o período desde o fim da repetição anterior.
- Durante a captura, quadros sem o ângulo de referência contam como descartados.

## Amplitudes do score

| Articulação | Movimento | Amplitude |
| --- | --- | --- |
| Ombro direito e esquerdo | Abdução | Ângulo do ombro |
| Quadril | Agachamento | `180° − quadril_dir` |
| Joelho | Agachamento | `180° − joelho_dir` |
| Tornozelo | Agachamento | `tornozelo_dir` em repouso − no pico |

Valores negativos viram 0. A amplitude final é a média das repetições válidas,
com 1 casa decimal. Sem posição inicial, não há medida do tornozelo.

## Nota, faixa e score

`R` é a referência da articulação.

| Amplitude em relação a R | Nota (linear em cada trecho) |
| --- | --- |
| 100% ou mais | 10 |
| 90% a 100% | 8 a 10 |
| 75% a 90% | 4 a 8 |
| 50% a 75% | 0 a 4 |
| Abaixo de 50% | 0 |

| Faixa | Critério |
| --- | --- |
| Adequada | 90% de R ou mais |
| Reduzida | De 75% a menos de 90% |
| Limitada | Abaixo de 75% |

O **score** é a média simples das 5 notas. Se faltar uma medida, não há score.
A tela mostra o valor arredondado para inteiro; o PDF, com 1 casa decimal.

## Meta

Para quem está abaixo de R, a meta soma à amplitude atual 10% de R a cada 3
meses (proporcional por mês), com ganho máximo de 15% de R por Jornada e sem
passar de R. Quem está em R ou acima mantém o valor.

A meta é uma simulação, não uma previsão de resultado. O teto de 15% ainda
precisa ser confirmado com o produto.

## Assimetria dos ombros

O alerta exige as duas condições:

- diferença de pelo menos **15%** em relação ao lado de maior amplitude; e
- diferença de pelo menos **10°**.

Ele não altera o score.

## Referências padrão

`MobilityReference.standard` vale para todos os perfis.

| Articulação | R | Origem |
| --- | --- | --- |
| Ombro direito | 150,6° | Gill et al. (2020), tabela 2 |
| Ombro esquerdo | 148,7° | Gill et al. (2020), tabela 2 |
| Quadril | 124,6° | Endo et al. (2020), tabela 1, lado direito |
| Joelho | 125,2° | Endo et al. (2020), tabela 1, lado direito |
| Tornozelo | 25,9° | Endo et al. (2020), tabela 1, lado direito |

Os valores dos ombros são médias ponderadas de 2.404 adultos (1.237 homens e
1.167 mulheres), reunindo as faixas etárias e os sexos.

- Gill et al., 2020, *BMC Musculoskeletal Disorders* 21:676,
  [doi:10.1186/s12891-020-03665-9](https://doi.org/10.1186/s12891-020-03665-9),
  CC BY 4.0.
- Endo, Miura e Sakamoto, 2020, *J Phys Ther Sci* 32(6):391–394,
  [doi:10.1589/jpts.32.391](https://doi.org/10.1589/jpts.32.391).

### Como interpretar

- R é uma **média** da amostra, não a amplitude máxima nem um limite clínico.
- O estudo dos ombros usou inclinômetro, não câmera.
- O estudo do agachamento tem só 9 homens, com idade média de 18,3 anos. O
  agachamento foi feito com os braços elevados, e o quadril foi medido em relação
  à pelve; a biblioteca mede em relação ao tronco.
- A flexão e a dorsiflexão da biblioteca ainda não foram validadas contra
  goniômetro.

Para usar outros valores, informe `PerfilAvaliado.referencia`. Cada avaliação
grava a referência usada, então mudanças na tabela não alteram o histórico.
Registros salvos sem referência usam `MobilityReference.illustrative` (ombros
150°, quadril 120°, joelho 140°, tornozelo 35°), marcada como provisória.
