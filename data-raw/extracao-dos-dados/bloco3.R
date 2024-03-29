library(microdatasus)
library(dplyr)
library(janitor)
library(readr)
library(openxlsx)
library(readxl)
library(stringr)
library(tidyr)

  df <- fetch_datasus(
    year_start = 2012,
    year_end = 2022,
    vars = c("CODMUNRES", "DTNASC", "CONSPRENAT", "MESPRENAT", "SEMAGESTAC"),
    information_system = "SINASC"
  )
  
  #write.csv(df, paste0("dados_sinasc_bloco3.csv"))


 df_proc <- process_sinasc(df, municipality_data = T) |>
   select(
     CODMUNRES,
     DTNASC,
     CONSPRENAT,
     MESPRENAT,
     SEMAGESTAC
   )
 
  df2 <- df |>
  mutate(
    ano = as.numeric(substr(DTNASC, 5, 8)),
    codmunres = as.numeric(CODMUNRES),
    CONSPRENAT = as.numeric(CONSPRENAT),
    MESPRENAT = as.numeric(MESPRENAT),
    SEMAGESTAC = as.numeric(SEMAGESTAC)
  ) |>  
  mutate(
    
    nascidos= 1,
    pelo_menos_uma_consulta_prenatal = case_when(
      CONSPRENAT >= 1 ~ 1,
      !(CONSPRENAT >= 1) ~0
    ),
    inicio_precoce_do_prenatal = case_when(
      (MESPRENAT ==  1 | MESPRENAT == 2 | MESPRENAT ==  3) ~ 1,
      !(MESPRENAT ==  1 | MESPRENAT == 2 | MESPRENAT ==  3) ~ 0
    ),
    mais_de_sete_consultas_prenatal = case_when(
      (CONSPRENAT > 7) ~ 1,
      !(CONSPRENAT > 7) ~ 0
      ),
    mulheres_com_consultas_prenatal_adequadas = case_when(
      ((SEMAGESTAC < 20 & CONSPRENAT >= 1) |
        (SEMAGESTAC >= 20 & SEMAGESTAC < 26 & CONSPRENAT >= 2) |
        (SEMAGESTAC >= 26 & SEMAGESTAC < 30 & CONSPRENAT >= 3) |
        (SEMAGESTAC >= 30 & SEMAGESTAC < 34 & CONSPRENAT >= 4) |
        (SEMAGESTAC >= 34 & SEMAGESTAC < 36 & CONSPRENAT >= 5) |
        (SEMAGESTAC >= 36 & SEMAGESTAC < 38 & CONSPRENAT >= 6) |
        (SEMAGESTAC >= 38 & SEMAGESTAC < 40 & CONSPRENAT >= 7) |
        (SEMAGESTAC >= 40 & CONSPRENAT >= 8)) ~ 1,
       
      !((SEMAGESTAC < 20 & CONSPRENAT >= 1) |
          (SEMAGESTAC >= 20 & SEMAGESTAC < 26 & CONSPRENAT >= 2) |
          (SEMAGESTAC >= 26 & SEMAGESTAC < 30 & CONSPRENAT >= 3) |
          (SEMAGESTAC >= 30 & SEMAGESTAC < 34 & CONSPRENAT >= 4) |
          (SEMAGESTAC >= 34 & SEMAGESTAC < 36 & CONSPRENAT >= 5) |
          (SEMAGESTAC >= 36 & SEMAGESTAC < 38 & CONSPRENAT >= 6) |
          (SEMAGESTAC >= 38 & SEMAGESTAC < 40 & CONSPRENAT >= 7) |
          (SEMAGESTAC >= 40 & CONSPRENAT >= 8)) ~ 0
    )
    
  ) |>
  #select(codmunres, ano, nascidos) |>
  group_by(codmunres, ano) |>
  summarise(
    total_de_nascidos_vivos = sum(nascidos),
    mulheres_com_pelo_menos_uma_consulta_prenatal = sum(pelo_menos_uma_consulta_prenatal, na.rm = T),
    mulheres_com_inicio_precoce_do_prenatal = sum(inicio_precoce_do_prenatal, na.rm = T),
    mulheres_com_mais_de_sete_consultas_prenatal = sum(mais_de_sete_consultas_prenatal, na.rm = T),
    mulheres_com_consultas_prenatal_adequadas = sum(mulheres_com_consultas_prenatal_adequadas, na.rm = T)
    ) |>
  ungroup()

#Criando um objeto que recebe os códigos dos municípios que utilizamos no painel
codigos_municipios <- read_csv("data-raw/extracao-dos-dados/databases-antigas/tabela_aux_municipios.csv") |>
  pull(municipio)

#Criando um data.frame auxiliar que possui uma linha para cada combinação de município e ano
df_aux_municipios <- data.frame(codmunres = rep(codigos_municipios, each = length(2012:2022)), ano = 2020:2022)

##Transformando as colunas que estão em caracter para numéricas
df2 <- df2 |> mutate_if(is.character, as.numeric)

##Fazendo um left_join da base auxiliar de municípios com o data.frame que contém o total de nascidos vivos
df_bloco3 <- left_join(df_aux_municipios, df2)

df_bloco3[is.na(df_bloco3)] <- 0


# Incidência de sífilis congênita por mil nascidos vivos ------------------
##Lendo a base de dados obtida pelo site http://indicadoressifilis.aids.gov.br/
df_sifilis_excel <- read_excel("Bloco_3/Databases/dados_painel_sifilis_2023.xlsx",
                               sheet = "DADOS CONTINUAÇÃO 2"
)

#Corrigindo os nomes das colunas e filtrando pelos municípios que utilizamos no painel
names(df_sifilis_excel) <- as.character(df_sifilis_excel[1,])

df_sifilis <- df_sifilis_excel[-1, ] |>
  clean_names() |>
  select(
    codmunres = codigo,
    starts_with("sifilis_congenita_em_menores_de_um_ano_2")
  ) |>
  rename_with(
    str_sub, start = -4, starts_with("sifilis_congenita_em_menores_de_um_ano_2")
  ) |>
  filter(codmunres %in% df_aux_municipios$codmunres) |>
  mutate_if(is.character, as.numeric)

#Passando para o formato long
df_sifilis_long <- df_sifilis |>
  pivot_longer(
    cols = !codmunres,
    names_to = "ano",
    values_to = "casos_sc"
  ) |>
  filter(ano <= 2022) |>
  mutate_if(is.character, as.numeric)

##Juntando com o restante da base do bloco 3
df_bloco3 <- left_join(df_bloco3, df_sifilis_long)

##Substituindo os NA's da coluna 'casos_sc' por 0 (gerados após o left_join)
df_bloco3$casos_sc[is.na(df_bloco3$casos_sc)] <- 0

# Salvando a base de dados completa -----------------
write.csv(df_bloco3, " data-raw/csv/indicadores_bloco3_assistencia_pre-natal_2012-2022.csv", row.names = FALSE)

