### ---- Load Packages and Functions  ####


pacman::p_load(tidyverse, janitor, highcharter, httr, furrr, lubridate, tidytext)

setwd(here::here())

color_dat <- tibble(
  colors = c("#00b13d", "#80c31c", "#0a2cca", "#008067", "#bf0000", "#ff0000", "#6f2421", "#02a6e9", "#92107d", "#04d3d4", "#242b57", "#66cdaa", "#242b57", "#006b28", "#012758", "#ea5b0b", "#582c83", "#698c0c", "#fdfd00", "#8da6d6"),
  party = c("D66", "GroenLinks", "VVD", "CDA", "SP", "PvdA", "FvD", "ChristenUnie", "50PLUS", "Alliantie", "BVNL", "DENK", "Ja21", "PvdD", "PVV", "SGP", "Volt Nederland", "BBB", "BIJ1", "NSC"))


if(!dir.exists("data")) dir.create("data")

get_mid <- function(spend_upper_bound, spend_lower_bound) {
  # (spend_upper_bound-spend_lower_bound)/2+spend_lower_bound
  (spend_upper_bound+spend_lower_bound)/2
}




wtm_data <- readRDS("data/all_dat.rds") %>% #names
  select(advertiser_id = page_id,
         advertiser_name = page_name)  %>%
  mutate(advertiser_id = as.character(advertiser_id))  
  # mutate(party = case_when(
  #   str_detect(advertiser_id, "638633769597292") ~ "ASh",
  #   T ~ party 
  # )) %>% 
  # filter(!(party %in% c("Vlada Crne Gore", "Drugo"))) %>% 
  # left_join(party_dict) %>% 
  # mutate(party = coalition)


assign_colors <- function(dat, n = 12) {
  
  color_sample <- colorspace::divergingx_hcl(n)
  
  lenght <- dat$color[is.na(dat$color)] %>% length
  
  if(lenght==0) return(invisible())
  
  cols <- sample(color_sample, lenght, replace = T)
  
  dat$color[is.na(dat$color)] <- cols
  
  return(dat)
  
}

unnest_geos <- function(x) {
  # cat(glue::glue("{x$row_number} out of {nrow(age_gender_targeted_raw)} ({round(100*x$row_number/nrow(age_gender_targeted_raw), 2)}%)\n\n"))
  x %>% 
    dplyr::pull(region_distribution) %>% 
    flatten() %>% 
    map_dfr(flatten) %>% 
    mutate(id = x$id)%>% 
    mutate(start_time = x$start_time)%>% 
    mutate(advertiser_name = x$advertiser_name)
}

unnest_dems <- function(x) {
  # cat(glue::glue("{x$row_number} out of {nrow(age_gender_targeted_raw)} ({round(100*x$row_number/nrow(age_gender_targeted_raw), 2)}%)\n\n"))
  x %>% 
    dplyr::pull(demographic_distribution) %>% 
    flatten() %>% 
    map_dfr(flatten) %>% 
    mutate(id = x$id)
}


last_updated_time <- as.character(Sys.time())

### ---- Get Facebook data  ####


cat("\n\nFB Data: Getting it\n\n")  

elex30 <- readRDS("data/election_dat30.rds") %>% 
  filter(is.na(no_data)) %>% 
  distinct(page_id, page_name, party)%>% 
  distinct(page_id, .keep_all = T)
# get_fb_ads <- function() {

# readRenviron(".Renviron")

token <- Sys.getenv("fb_token")

#link to fb api
my_link<- "https://graph.facebook.com"

#define fields you are interested in
search_fields=c("ad_creation_time", 
                "ad_delivery_start_time",
                "ad_delivery_stop_time",
                "ad_creative_link_caption",
                "ad_creative_link_description",
                "ad_creative_link_title",
                "age_country_gender_reach_breakdown",
                "beneficiary_payers",
                "bylines",
                "delivery_by_region",
                "estimated_audience_size",
                "eu_total_reach",
                "languages",
                "target_ages",
                "target_gender",
                "target_locations",
                "currency",
                "ad_creative_body", 
                "page_id",
                "page_name",
                "spend",
                "ad_snapshot_url",
                "demographic_distribution",
                "funding_entity",
                "potential_reach",
                "publisher_platforms",
                "impressions",
                "region_distribution") %>% 
  stringr::str_c(., collapse=", ")

min_date <- "2023-08-01"

get_em <- function(pgid, pgname) {
  
  # print(pgid)
  
  print(paste0(pgid, ": ", pgname))
  #get the data from the first 'page' of data the api provides
  page_one_response <- GET(my_link,
                           path = "/ads_archive",
                           query = list(access_token = token,
                                        limit=50,
                                        ad_type="POLITICAL_AND_ISSUE_ADS",
                                        ad_active_status="ALL",
                                        search_terms="''",
                                        search_page_ids=pgid,
                                        # ad_delivery_date_min = min_date,
                                        fields=search_fields,
                                        ad_reached_countries="NL"))
  # print(page_one_response)
  page_one_content<<- content(page_one_response)
  
  x <- tibble(data=page_one_content$data)
  df_imp <- x %>% 
    unnest_wider(data) 
  
  #get the link refering to the next page
  next_link <- page_one_content$paging$`next`
  
  page <- 1
  
  #iterate over all pages until there is no further page
  while(length(next_link)>0) {
    # try({
    
    # Sys.sleep(5)
      
      next_response <- GET(next_link)
      next_content<- content(next_response)
      
      # print(next_content$data)
      
      if(!is.null(next_content$data)){
        y <- tibble(data=next_content$data)
        df_next <- y %>% 
          unnest_wider(data) 
        
        print(nrow(df_next))
        
        df_imp <- bind_rows(df_imp, df_next)  
        
        next_link <- next_content$paging$`next`
        
        page <- page + 1       
      } else {
        next_link <- NULL
      }
      
    
    # })
    # while(T) {
    
  }
  
  return(df_imp)
  
}

get_em <- possibly(get_em, otherwise = NULL, quiet = F)

# debugonce(get_em)

df_imp <- elex30 %>% 
  # filter(page_id == "137011549489828") %>%
  # slice(92) %>% 
  # pull(page_id) %>% 
  # .[1] %>% 
  split(1:nrow(.)) %>% 
  map_dfr_progress(~get_em(.x$page_id, .x$page_name))

saveRDS(df_imp2, "data/df_impday.rds")

df_imp %>% 
  filter(page_id == "320374518118") %>% View()

options(scipen = 999)


fb_dat <- readRDS("data/fb_dat.rds")

library(metatargetr)


# end <-  %>% 
#   map_dfr_progress(get_ad_snapshots, mediadir  = "media")
hash_table <- read_csv("media/hash_table.csv")

already_theres <- hash_table  %>% 
  distinct(ad_id) %>% 
  pull(ad_id) %>% 
  str_remove_all("adid_|_[:digit:]|_[:digit:][:digit:]")

theids <- fb_dat %>% 
  distinct(id) %>% 
  pull(id) %>% 
  setdiff(already_theres)

# already_theres %>% setdiff("698466622222397")

for (jj in seq_along(theids)) {
  print(glue::glue("{jj} out of {length(theids)} ({round(jj/length(theids)*100, 2)}%)"))
  get_ad_snapshots(theids[jj], download = T, hashing = T, mediadir = "media")
}




fb_dat %>% #View()
  select(id, advertiser_name, advertiser_id, impressions, spend, eu_total_reach, ad_delivery_start_time, ad_delivery_stop_time) %>% 
  left_join(elex30 %>% select(advertiser_id = page_id, party)) %>% 
   mutate(start = lubridate::ymd(ad_delivery_start_time)) %>% 
  filter(start >= lubridate::ymd("2023-08-01")) %>% 
  filter(start <= lubridate::ymd("2023-11-22")) %>% 
  unnest_wider(impressions) %>% 
  rename(imp_lower = lower_bound)%>% 
  rename(imp_upper = upper_bound) %>% 
unnest_wider(spend) %>% 
  rename(spend_lower = lower_bound)%>% 
  rename(spend_upper = upper_bound) %>% 
  glimpse() %>% 
  mutate(spend_lower = ifelse(spend_lower==0,1, spend_lower)) %>% 
  # filter(eu_total_reach!=1) %>%
  mutate(price = as.numeric(spend_lower)/as.numeric(imp_lower)*1000) %>% #View()
  add_count(advertiser_name) %>% 
  filter(n > 20) %>%
  # filter(price <= 100) %>% 
  mutate(party = fct_reorder(party, price)) %>% 
  mutate(advertiser_name = fct_reorder(advertiser_name, price)) %>% 
  # drop_na(party) %>% 
  # ggplot(aes(party, price)) +
  ggplot(aes(advertiser_name, price)) +
  # geom_histograCm() +
  geom_boxplot() +
  stat_summary(fun.y=mean, geom="point", shape=20, size=3, color="red", fill="red") +
  
  # scale_y_log10() +
  coord_flip() +
  EnvStats::stat_n_text() +
  stat_summary(
    fun=median, 
    geom="label", 
    aes(label=round(..y.., 1)), 
    vjust=1, 
    hjust=-0.3,  # Adjust this value to move text left or right
    color="black"
  ) +
  ylim(0, 100) +
  theme_minimal()
  # EnvStats::stat_median_iqr_text()

ggsave("img/pay.png", width = 14, height = 10, dpi = 900, bg = "white")


fb_dat %>% #View()
  select(id, advertiser_name, advertiser_id, impressions, spend, eu_total_reach, ad_delivery_start_time, ad_delivery_stop_time) %>% 
  left_join(elex30 %>% select(advertiser_id = page_id, party)) %>% 
  mutate(start = lubridate::ymd(ad_delivery_start_time)) %>% 
  filter(start >= lubridate::ymd("2023-08-01")) %>% 
  unnest_wider(impressions) %>% 
  rename(imp_lower = lower_bound)%>% 
  rename(imp_upper = upper_bound) %>% 
  unnest_wider(spend) %>% 
  rename(spend_lower = lower_bound)%>% 
  rename(spend_upper = upper_bound) %>% 
  glimpse() %>% 
  mutate(spend_lower = ifelse(spend_lower==0,1, spend_lower)) %>% 
  filter(eu_total_reach!=1) %>%
  mutate(price = as.numeric(spend_lower)/as.numeric(eu_total_reach)*1000) %>% #View()
  add_count(advertiser_name) %>% 
  # filter(n > 10) %>% 
  # filter(price <= 100) %>% 
  mutate(party = fct_reorder(party, eu_total_reach)) %>% 
  drop_na(party) %>% 
  ggplot(aes(party, eu_total_reach)) +
  # geom_histograCm() +
  geom_boxplot() +
  stat_summary(fun.y=mean, geom="point", shape=20, size=3, color="red", fill="red") +
  
  # scale_y_log10() +
  coord_flip() +
  EnvStats::stat_n_text() +
  stat_summary(
    fun=median, 
    geom="label", 
    aes(label=round(..y.., 1)), 
    vjust=1, 
    hjust=-0.3,  # Adjust this value to move text left or right
    color="black"
  ) 


fb_dat %>% #View()
  # select(estimated_audience_size)
  select(id, advertiser_name, advertiser_id, estimated_audience_size, impressions, spend, eu_total_reach, ad_delivery_start_time, ad_delivery_stop_time) %>% 
  left_join(elex30 %>% select(advertiser_id = page_id, party)) %>% 
  mutate(start = lubridate::ymd(ad_delivery_start_time)) %>% 
  filter(start >= lubridate::ymd("2023-08-01")) %>% 
  unnest_wider(impressions) %>% 
  rename(imp_lower = lower_bound)%>% 
  rename(imp_upper = upper_bound) %>% 
  unnest_wider(spend) %>% 
  rename(spend_lower = lower_bound)%>% 
  rename(spend_upper = upper_bound) %>% 
  unnest_wider(estimated_audience_size) %>% 
  rename(ausize_lower = lower_bound)%>% 
  rename(ausize_upper = upper_bound) %>% 
  glimpse() %>% 
  mutate(spend_lower = ifelse(spend_lower==0,1, spend_lower)) %>% 
  # filter(eu_total_reach!=1) %>%
  mutate(price = as.numeric(spend_lower)/as.numeric(eu_total_reach)*1000) %>% #View()
  mutate(ausize_lower = as.numeric(ausize_lower)) %>% 
  add_count(advertiser_name) %>% 
  # filter(n > 10) %>% 
  # filter(price <= 100) %>% 
  mutate(ausize_lower = as.factor(ausize_lower) %>% as.numeric) %>% 
  mutate(party = fct_reorder(party, ausize_lower)) %>% 
  drop_na(party) %>% 
  ggplot(aes(party, ausize_lower)) +
  # geom_histograCm() +
  geom_boxplot() +
  stat_summary(fun.y=mean, geom="point", shape=20, size=3, color="red", fill="red") +
  
  # scale_y_log10() +
  coord_flip() +
  EnvStats::stat_n_text() +
  stat_summary(
    fun=median, 
    geom="label", 
    aes(label=round(..y.., 1)), 
    vjust=1, 
    hjust=-0.3,  # Adjust this value to move text left or right
    color="black"
  ) 


fb_dat %>% #View()
  select(id, advertiser_name, advertiser_id, impressions, spend, eu_total_reach, ad_delivery_start_time, ad_delivery_stop_time) %>% 
  mutate(start = lubridate::ymd(ad_delivery_start_time)) %>% 
  filter(start >= lubridate::ymd("2023-08-01")) %>% 
  unnest_wider(impressions) %>% 
  rename(imp_lower = lower_bound)%>% 
  rename(imp_upper = upper_bound) %>% 
  unnest_wider(spend) %>% 
  rename(spend_lower = lower_bound)%>% 
  rename(spend_upper = upper_bound) %>% 
  glimpse() %>% 
  mutate(spend_lower = ifelse(spend_lower==0,1, spend_lower)) %>% 
  # filter(eu_total_reach!=1) %>%
  mutate(eu_total_reach = as.numeric(eu_total_reach)) %>% 
  mutate(imp_lower = as.numeric(imp_lower)) %>% 
  mutate(price = as.numeric(spend_lower)/as.numeric(eu_total_reach)*1000) %>% #View()
  add_count(advertiser_name) %>% 
  filter(n > 10) %>% 
  filter(spend_lower > 1) %>% 
  arrange(desc(price)) %>% 
  mutate(diff = imp_lower-eu_total_reach) %>% View()

# df_imp2 <- df_imp
# saveRDS(df_imp2, "data/df_imp2.rds")
# dutch_parties <- c("VVD", "D66", "FvD", "SP", "GroenLinks", "Volt Nederland", "PvdA", "CDA", "PvdD", "ChristenUnie", "SGP", "DENK", "50PLUS")

cat("\n\nFB Data: Read in old data\n\n")  

# fb_dat <- readRDS("data/fb_dat.rds")


# fb_dat <- fb_dat %>% 
#   mutate(advertiser_id = ifelse(is.na(advertiser_id), page_id, advertiser_id))


# saveRDS(df_imp, "data/df_imp.rds")
# df_imp <- readRDS("data/df_imp.rds")

cat("\n\nFB Data: Merge data\n\n")  


fb_dat <- df_imp %>% 
  # bind_rows(df_imp2) %>% 
  rename(advertiser_name = page_name) %>% 
  rename(advertiser_id = page_id) %>% 
  bind_rows(fb_dat) %>%
  distinct(id, .keep_all = T) #%>%
  # left_join(wtm_data %>% select(-advertiser_name)) #%>% 
  # mutate(advertiser_name = case_when(
  #   advertiser_name == 'Partij voor de Dieren' ~ "PvdD",
  #   advertiser_name == 'Partij van de Arbeid (PvdA)' ~ "PvdA",
  #   advertiser_name == 'Forum voor Democratie -FVD' ~ "FvD",
  #   advertiser_name == '50PLUSpartij' ~ "50PLUS",
  #   T ~ advertiser_name
  # ))

saveRDS(fb_dat, "data/fb_dat.rds")

# fb_dat %>% dplyr::filter(advertiser_name == "BIJ1")

# saveRDS(fb_dat, "fb_dat/fb_dat_old.rds")


cat("\n\nFB Data: Save data\n\n")  

fb_dat <- readRDS("data/fb_dat.rds")

rm(df_imp)
gc()

cat("\n\nGarbage collected\n\n")  


# rstudioapi::jobRunScript("get_fb.R")


# fb_dat_parties <- fb_dat %>% 
#   mutate(ad_delivery_start_time = as.Date(ad_delivery_start_time)) %>% 
#   filter(ad_delivery_start_time >= as.Date("2020-09-01")) %>% 
#   filter(advertiser_name %in% dutch_parties) 
# 
# saveRDS(fb_dat_parties, "fb_dat/fb_dat_parties.rds")

#   return(fb_dat)
#   
# }

# fb_ads <- get_fb_ads()

# color_dat <- tibble(
#   color = c("#00b13d", "#80c31c", "#cd503e", "#008067", "#6f2421", "#e3101c", "#e01003", "#036b2c", "#02a6e9", "#562883", "#eeaa00", "#34c1c4", "#92107d", "#202122", "#242b57"),
#   advertiser_name = c("D66", "GroenLinks", "VVD", "CDA", "FvD", "PvdA", "SP", "PvdD", "ChristenUnie", "Volt Nederland", "SGP", "DENK", "50PLUS", "BIJ1", "Ja21"))

cat("\n\nFB Data: Get totals\n\n")  


total_times <- fb_dat %>% 
  mutate(date_range_start = as.Date(ad_delivery_start_time)) %>%
  filter(date_range_start >= as.Date(min_date)) %>% 
  unnest_wider(spend, names_sep = "_") %>%
  unnest_wider(impressions, names_sep = "_") %>% 
  unnest_wider(potential_reach , names_sep = "_") %>%
  mutate_at(vars(spend_lower_bound, spend_upper_bound, 
                 impressions_lower_bound, impressions_upper_bound, 
                 potential_reach_lower_bound, potential_reach_upper_bound), as.numeric) %>% 
  # drop_na(spend_lower_bound, spend_upper_bound, impressions_lower_bound, impressions_upper_bound) %>% 
  mutate(impressions_lower_bound = case_when(
    # is.na(impressions_upper_bound) ~ 0, 
    # is.na(impressions_lower_bound) ~ 0,
    impressions_lower_bound == 0 ~ 1, 
    T ~ impressions_lower_bound)) %>% 
  mutate(spend_lower_bound = case_when(
    spend_lower_bound == 0 ~ 1, 
    T ~ spend_lower_bound)) %>% 
  drop_na(impressions_lower_bound, impressions_upper_bound)  
# batch_id_dat <- total_times  %>% 
#   # filter(is.na(advertiser_id)) %>% View
#   mutate(unique_advertiser_id = as.numeric(as.factor(advertiser_name))) %>% 
#   group_by(ad_creative_body, ad_creative_link_title, advertiser_name, advertiser_id) %>% 
#   mutate(batch_id = paste0(unique_advertiser_id, "_", n(), "_", sample(10000:10000000000, size = 1)))%>% 
#   ungroup() %>% 
#   select(id, batch_id)

facebook_id_dat <- total_times  %>% 
  distinct(advertiser_name, .keep_all = T) %>% 
  select(advertiser_name, advertiser_id)

# total_times %>% filter(advertiser_name == "AeroTime") %>% View

fb_total <- total_times  %>% 
  # left_join(batch_id_dat) %>% 
  group_by(party) %>% 
  summarise(potential_reach_min = sum(potential_reach_lower_bound),
            # potential_reach_max = median(potential_reach_upper_bound) ,
            # potential_reach_mid = median(get_mid(potential_reach_lower_bound, potential_reach_upper_bound)),
            spend_range_min = sum(spend_lower_bound) ,
            spend_range_max = sum(spend_upper_bound) ,
            spend_range_mid = sum(get_mid(spend_lower_bound, spend_upper_bound)) ,
            impressions_range_min = sum(impressions_lower_bound) ,
            impressions_range_max = sum(impressions_upper_bound) ,
            impressions_range_mid = sum(get_mid(impressions_lower_bound, impressions_upper_bound)),
            n_ids = n()) %>% 
  ungroup() %>% 
  left_join(color_dat)
# left_join(total_spend_fb)

cat("\n\nFB Data: Get times\n\n")  


# tidytemplate::save_it(fb_total)

fb_times <- total_times %>% 
  # left_join(batch_id_dat) %>% 
  # group_by(batch_id) %>% 
  # mutate(date_range_start = min(date_range_start)) %>% 
  # ungroup() %>% 
  group_by(party, date_range_start) %>% 
  # group_by(date_range_start, ad_creative_body, ad_creative_link_title, advertiser_name) %>% 
  summarise(potential_reach_min = sum(potential_reach_lower_bound) ,
            # potential_reach_max = sum(potential_reach_upper_bound) ,
            # potential_reach_mid = sum(get_mid(potential_reach_lower_bound, potential_reach_upper_bound)),
            spend_range_min = sum(spend_lower_bound) ,
            spend_range_max = sum(spend_upper_bound) ,
            spend_range_mid = sum(get_mid(spend_lower_bound, spend_upper_bound)) ,
            impressions_range_min = sum(impressions_lower_bound) ,
            impressions_range_max = sum(impressions_upper_bound) ,
            impressions_range_mid = sum(get_mid(impressions_lower_bound, impressions_upper_bound)) ,
            n_ids = n()) %>% 
  ungroup() %>% 
  complete(party, date_range_start = seq.Date(min(date_range_start), max(date_range_start), by="day"), fill = list(n = 0, spend_range_min = 0, spend_range_mid = 0, spend_range_max = 0, impressions_range_min = 0, impressions_range_mid = 0, impressions_range_max = 0, potential_reach_min = 0)) %>% 
  filter(party != 0) %>% 
  left_join(color_dat)

cat("\n\nFB Data: Get age/gender I\n\n")  


age_gender_targeted_raw <- fb_dat %>% 
  mutate(start_time = lubridate::as_datetime(ad_delivery_start_time) %>% lubridate::floor_date("day")) %>% 
  mutate(start_time = as.Date(start_time)) %>% 
  mutate(date_range_start = as.Date(ad_delivery_start_time)) %>%
  filter(date_range_start >= as.Date(min_date)) 

cat("\n\nFB Data: Get age/gender II\n\n")  

unnest_dems <- possibly(unnest_dems, otherwise = NULL, quiet = F)

age_gender_targeted <- age_gender_targeted_raw %>% 
  # slice(1) %>% 
  mutate(row_number = 1:n()) %>% 
  split(1:nrow(.)) %>% 
  map_dfr(unnest_dems) %>% 
  right_join(age_gender_targeted_raw)


cat("\n\nFB Data: Get age/gender III\n\n")  

### Facebook setup
# dutch_parties_fb <- c("VVD", "D66", "FvD", "SP", "GroenLinks", "Volt Nederland", "PvdA", "CDA", "PvdD", "ChristenUnie", "SGP", "DENK", "50PLUS", "BIJ1", "Ja21")


fb_gender <- age_gender_targeted  %>% 
  # filter(advertiser_id %in% dutch_parties_fb) %>%
  mutate(percentage = as.numeric(percentage)) %>% 
  mutate(gender_age = paste(gender, age)) %>% 
  filter(!str_detect(gender_age, "unknown")) %>% 
  filter(!str_detect(gender_age, "13-17")) %>% 
  filter(!str_detect(gender_age, "All")) %>% 
  drop_na(gender) %>% 
  group_by(advertiser_id) %>% 
  complete(id, gender, age, fill = list(percentage = 0)) %>% 
  ungroup() %>% 
  group_by(id, gender, advertiser_id) %>% 
  summarize(percentage = sum(percentage)) %>% 
  ungroup() #%>% 
  # mutate(percentage = round(percentage * 100, 2)) %>% 
  # left_join(facebook_id_dat)  #%>% 
# filter(advertiser_name == "PvdA")

cat("\n\nFB Data: Get age/gender IV\n\n")  



fb_age <- age_gender_targeted  %>% 
  mutate(percentage = as.numeric(percentage)) %>% 
  mutate(gender_age = paste(gender, age)) %>% 
  filter(!str_detect(gender_age, "unknown")) %>% 
  filter(!str_detect(gender_age, "13-17")) %>% 
  filter(!str_detect(gender_age, "All")) %>% 
  group_by(advertiser_id) %>% 
  complete(id, gender, age, fill = list(percentage = 0)) %>% 
  ungroup() %>% 
  group_by(id, age, advertiser_id) %>% 
  summarize(percentage = sum(percentage)) %>% 
  ungroup() #%>% 
  # mutate(percentage = round(percentage * 100, 2)) %>% 
  # left_join(facebook_id_dat) 


fb_reach <- total_times  %>% 
  # left_join(batch_id_dat) %>% 
  group_by(advertiser_id) %>% 
  summarise(potential_reach_min = sum(potential_reach_lower_bound),
            n_ids = n()) %>% 
  ungroup() 

fb_total <- fb_total %>%
  rename(advertiser_name = party)

fb_times <- fb_times %>%
  rename(advertiser_name = party)

fb_gender <- fb_gender %>% 
  left_join(wtm_data) %>% 
  left_join(color_dat) #%>%
  # rename(advertiser_name = party)

fb_age <- fb_age %>% 
  left_join(wtm_data) %>% 
  left_join(color_dat) #%>%
  # rename(advertiser_name = party)

fb_reach <- fb_reach %>% 
  left_join(wtm_data) %>% 
  left_join(color_dat) #%>%
  # rename(advertiser_name = party)


fb_aggr <- list(total = fb_total, times = fb_times,
                gender = fb_gender,
                age = fb_age, reach = fb_reach)

### create graph ######

# color_dat <- tibble(
#   color = c("#00b13d", "#80c31c", "#cd503e", "#008067", "#6f2421", "#e3101c", "#e01003", "#036b2c", "#02a6e9", "#562883", "#eeaa00", "#34c1c4", "#92107d", "#202122", "#242b57"),
#   advertiser_name = c("D66", "GroenLinks", "VVD", "CDA", "FvD", "PvdA", "SP", "PvdD", "ChristenUnie", "Volt Nederland", "SGP", "DENK", "50PLUS", "BIJ1", "Ja21")) %>% 
#   mutate(advertiser_name = as.factor(advertiser_name))


# fb_aggr$report_spending <- spending
# fb_aggr$report_spending_loc <- spending_loc


saveRDS(fb_aggr, file = "data/fb_aggr.rds")




cat("\n\nFB Data: Done\n\n") 