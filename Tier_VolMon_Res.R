library(tidyverse)
library(sqldf)
library(RODBC)

#This prevents scientific notation from being used and forces all imported fields to be character or numeric
options('scipen' = 50, stringsAsFactors = FALSE)

#############################################################################################
###                                  Load data from database                              ###
#############################################################################################


ch <- odbcConnectAccess2007("//deqlab1/wqm/Volunteer Monitoring/datamanagement/VolWQdb.mdb", case="nochange")




## Pull Preliminary Results from VolWQdb 
res <-
  sqlQuery(
    ch,
    "SELECT t_Result.ResultID, t_Result.ActivityID, t_Result.CharID, t_Result.Result, t_Result.RsltQual, t_Result.Unit, t_Result.Method, t_Result.MethodSpeciation, t_Result.RsltType, t_Result.AnalyticalLaboratory, t_Result.AnalyticalStartTime, t_Result.AnalyticalStartTimeZone, t_Result.AnalyticalEndTime, t_Result.AnalyticalEndTimeZone, t_Result.LabCommentCode, t_Result.LOQ, t_Result.LOQ_Unit, t_Result.QCorigACC, t_Result.QCorigPREC, t_Result.QCorigDQL, t_Result.DEQ_ACC, t_Result.DEQ_PREC, t_Result.BiasValue, t_Result.PrecisionValue, t_Result.ORDEQ_DQL, t_Result.StatisticalBasis, t_Result.RsltTimeBasis, t_Result.StoretQual, t_Result.RsltStatus, t_Result.Org_RsltComment, t_Result.DEQ_RsltComment
    FROM t_Result
    WHERE (((t_Result.RsltStatus)='Preliminary'));
    "
  )

## pull t_anomaly from VolWQdb
anom <- sqlFetch(ch, "t_Anomaly")

## pull t_ActGrp from VolWQdb
Actgrp <- sqlFetch(ch, "tjct_ActGrp2Act") 

## pull t_Activity from VolWQdb
Act <-sqlFetch(ch, "t_Activity")


odbcClose(ch)



##############################################################################################
###             Combine results with activity and activity group information               ###
##############################################################################################



# adds activity data to the resutls table
res_act <- merge(res, Act, by = "ActivityID", all.x = TRUE)

#adds Activity Group data to results - activity table
res_act_grp <-
  merge(res_act, Actgrp, by = "ActivityID", all.x = TRUE) %>%
  mutate(ActGrpID = ifelse(is.na(ActGrpID), "XXXX",ActGrpID)) %>%
  mutate(sub_char = paste(SubID, CharID, sep = "-")) %>%
  mutate(actgrp_char = paste(ActGrpID, CharID, sep = "-"))




###################################################################################################
###                                         QAQC Information                                    ###
###################################################################################################

#Create table of only QAQC Samples and their precision grades
# add storet qual
res_QAQC <- res_act_grp %>%
  filter(
    ActivityType != "FM",
    ActivityType != "FMC",
    ActivityType != "FMDL",
    ActivityType != "LSR"
  )  %>%
  select(
    ResultID,
    CharID,
    SubID,
    ActGrpID,
    actgrp_char,
    ActivityType,
    ActivityID,
    SubID,
    StartDateTime,
    DEQ_PREC,
    QCorigDQL,
    sub_char,
    StoretQual
  )

#Create a table that counts Grade types by actgrp_char
QAQC_grade_count <- res_QAQC %>%
  mutate(A = ifelse(DEQ_PREC == 'A', 1, 0)) %>%
  mutate(B = ifelse(DEQ_PREC == 'B', 1, 0)) %>%
  mutate(C = ifelse(DEQ_PREC == 'C', 1, 0)) %>%
  mutate(E = ifelse(DEQ_PREC == 'E', 1, 0)) %>%
  group_by(actgrp_char) %>%
  summarize(
    countofQAQC = n(),
    sumofA = sum(A),
    sumofB = sum(B),
    sumofC = sum(C),
    sumofE = sum(E)
  ) %>%
  mutate(
    pctA = (sumofA / countofQAQC),
    pctB = (sumofB / countofQAQC),
    pctC = (sumofC / countofQAQC),
    pctE = (sumofE / countofQAQC)
  )


#QC grades per sub, used for deault method
QAQC_grades_per_sub <-  res_QAQC %>%
  mutate(A = ifelse(DEQ_PREC == 'A', 1, 0)) %>%
  mutate(B = ifelse(DEQ_PREC == 'B', 1, 0)) %>%
  mutate(C = ifelse(DEQ_PREC == 'C', 1, 0)) %>%
  mutate(E = ifelse(DEQ_PREC == 'E', 1, 0)) %>%
  group_by(sub_char) %>%
  summarize(
    countofQAQC = n(),
    sumofA = sum(A),
    sumofB = sum(B),
    sumofC = sum(C),
    sumofE = sum(E)
  ) %>%
  mutate(
    subpctA = (sumofA / countofQAQC),
    subpctB = (sumofB / countofQAQC),
    subpctC = (sumofC / countofQAQC),
    subpctE = (sumofE / countofQAQC)
  ) %>%
  select(sub_char, countofQAQC, subpctA, subpctB, subpctC, subpctE)


# count number of duplicates per submission ID
QAQC_num_dup_by_sub <- res_act_grp %>%
  mutate(Count_of_sub_Q = (if_else((ActivityType == "QFQMR" | ActivityType == "QLQD"), 1, 0))) %>%
  group_by(sub_char) %>%
  summarise(Count_of_sub_QC = sum(Count_of_sub_Q))



#Table for number of QAQC Samples Per activity group
QAQC_num_dup_by_act_grp <- res_act_grp %>%
  mutate(Count_of_act_Q = (if_else((ActivityType == "QFQMR" | ActivityType == "QLQD"), 1, 0)),
         Count_of_act_non_Q = (if_else((ActivityType == "QFQMR" | ActivityType == "QLQD"), 0, 1))) %>%
  group_by(actgrp_char, sub_char) %>%
  summarise(Count_of_act_QC = sum(Count_of_act_Q),
            Count_of_act_noQC = sum(Count_of_act_non_Q)) %>%
  full_join(QAQC_num_dup_by_sub, by = "sub_char")
 


#Combine number of QAQC samples with precision grades
Act_grp_char_QAQC <- QAQC_num_dup_by_act_grp %>%
  full_join(QAQC_grade_count, by = "actgrp_char") %>%
  full_join(QAQC_grades_per_sub, by = "sub_char") %>%
  replace(is.na(.), 0)



#############################################################################################
###                                       Grading                                         ###
#############################################################################################

#assign preliminary DQLs to an Activity group characteristic
grade_Act_grp_prelim_grade <- Act_grp_char_QAQC %>%
  mutate(prelim_dql = ifelse(Count_of_act_QC / Count_of_act_noQC < 0.1, paste0("QC ", as.integer((Count_of_act_QC / Count_of_act_noQC)*100),"%"),
                      ifelse(pctA == 1, "A", #100% QC samples = A assign A
                      ifelse(pctB == 1, "B", #100% QC samples = B assign B
                      ifelse(pctC == 1, "C", #100% QC samples = C assign C
                      ifelse(pctA == 0 & pctB == 0 & pctC == 0, 
                             #default QC method if no QC samples
                             #if submission has >5 QC samples, 100% of those are A or B, and 
                             #=> 90% are A, then use B. Else, E
                             ifelse(Count_of_sub_QC > 5 & subpctA + subpctB == 1 & subpctA >= 0.90, "B", "E"), 
                      ifelse(pctA < 1 | pctB < 1 | pctC < 1 | pctE < 1, "Mixed", #if grades are mixed, assign mixed
                            "not yet graded"))))))) %>% #Should never be "not yet graded" 
  select(actgrp_char, sub_char, prelim_dql)  #pare down table to make more manageable 

mixed <- grade_Act_grp_prelim_grade %>%
  filter(prelim_dql == "Mixed")


#Push act_grp prelim DQLs to results
grade_res_prelim_DQL <- full_join(res_act_grp, grade_Act_grp_prelim_grade, by = "actgrp_char")


#pull out results with mixed grades
grade_mixed_res_prelim_dql <- grade_res_prelim_DQL %>%
  filter(prelim_dql == "Mixed") 



#pull out QC samples with mixed grades
Grade_mixed_QC <- grade_res_prelim_DQL %>%
  filter(prelim_dql == "Mixed") %>%
  filter(ActivityType == "QFQMR" | ActivityType == "QLQD") %>%
  arrange(actgrp_char)

#sort out some date issues
Grade_mixed_QC$StartDateTime = as.POSIXct(Grade_mixed_QC$StartDateTime, format = "%m/%d/%Y")
grade_mixed_res_prelim_dql$StartDateTime = as.POSIXct(grade_mixed_res_prelim_dql$StartDateTime, format = "%m/%d/%Y")



# Add a column for end of applicable day of a DQL using lag
# Add another column to indicate a row contains Max date for that group
QC_Mod <- Grade_mixed_QC %>%
  group_by(actgrp_char) %>%
  mutate(groupposition = 1:n(),
         IsMaxDate = ifelse(StartDateTime == max(StartDateTime),1,0),
         MaXDate = max(StartDateTime)) %>%
  mutate(ApplicableAfter =if_else(DEQ_PREC > lead(DEQ_PREC, n = 1) & groupposition == 1, StartDateTime,
                                  if_else(DEQ_PREC > lag(DEQ_PREC, n = 1), lag(StartDateTime),
                                  if_else(DEQ_PREC > lead(DEQ_PREC, n = 1), StartDateTime, 
                                  if_else(StartDateTime == MaXDate, StartDateTime, StartDateTime + 100))))) %>%
    ungroup() %>%
  group_by(actgrp_char, StartDateTime) %>%
  #if more than 1 QC sample exists for a day, choose the lowest value 
  #(max is used because A < B )
  mutate(Mod_DEQ_PREC = max(DEQ_PREC)) %>%
  as.data.frame()

QCmodtest <- QC_Mod %>%
  filter(actgrp_char == "0050-20130813-ec") %>%
  select(ResultID, StartDateTime, DEQ_PREC,IsMaxDate, ApplicableAfter, MaXDate, Mod_DEQ_PREC, groupposition )

  
# Join the data.frames to find DQL value
# I don't know how this works. I pulled it off the internet
# This should perform "grade spreading"

grade_mixed_result <-
  sqldf(
    "SELECT grade_mixed_res_prelim_dql.actgrp_char, grade_mixed_res_prelim_dql.ResultID, 
            grade_mixed_res_prelim_dql.Result,  grade_mixed_res_prelim_dql.StartDateTime ,
            QC_Mod.DEQ_PREC as prelim_dql
    FROM grade_mixed_res_prelim_dql, QC_Mod
    WHERE grade_mixed_res_prelim_dql.actgrp_char == QC_Mod.actgrp_char AND
    (
    (grade_mixed_res_prelim_dql.StartDateTime <= QC_Mod.StartDateTime AND QC_Mod.groupposition == 1) 
       OR
           (grade_mixed_res_prelim_dql.StartDateTime <= QC_Mod.StartDateTime AND QC_Mod.ApplicableAfter IS NULL) 
       OR
          (QC_Mod.ApplicableAfter IS NOT NULL AND grade_mixed_res_prelim_dql.StartDateTime > QC_Mod.ApplicableAfter) 
       OR
    (grade_mixed_res_prelim_dql.StartDateTime > QC_Mod.StartDateTime AND QC_Mod.IsMaxDate == 1)
    )"
)

#######
######
#####
####
###
## 
# below is the prelim grade table


#merge mixed reults back into table
grade_prelim_DQL <- merge(grade_res_prelim_DQL, grade_mixed_result, by = "ResultID", all.x = T ) %>%
  #if grade is mixed, assign new spread out grade, else use original grade
  mutate(prelim_DQL = ifelse(!is.na(prelim_dql.y), prelim_dql.y, prelim_dql.x)) %>% 
  #If result is a QC sample, use the grade from QC sample. Some days have more than 1 QC sample 
  #and grade_mixed_result assigns lowest grade for the day. This ensures QC results retain
  #original grade 
  mutate(prelim_DQL = ifelse(DEQ_PREC == "" | is.na(DEQ_PREC), prelim_DQL, DEQ_PREC)) %>%
  #below here is just cleanup from the merge process
  mutate(Result = Result.x) %>%
  mutate(StartDateTime = StartDateTime.x) %>%
  mutate(actgrp_char = actgrp_char.x) %>%
  mutate(sub_char = sub_char.x) %>%
  select(
    -Result.x,
    -Result.y,
    -actgrp_char.x,
    -actgrp_char.y,
    -prelim_dql.x,
    -prelim_dql.y,
    -StartDateTime.x,
    -StartDateTime.y,
    -sub_char.x,
    -sub_char.y
  ) %>%
  mutate(resactgrp = paste(ResultID, actgrp_char, sep = "-"))

test <- grade_prelim_DQL %>%
  filter(grepl("0050-",ResultID),
         CharID == "ec") %>%
  arrange(CharID, StartDateTime)


# Check work:
# write.csv(Grade_mixed_QC, file = "Grade_mixed_QC.csv")
# write.csv(grade_mixed_result, file = "grade_mixed_result.csv")
# write.csv(QC_Mod, file = "QC_Mod.csv")
# write.csv(grade_prelim_DQL, file = "grade_prelim_DQL.csv")
# write.csv(grade_res_prelim_DQL, file = "grade_res_prelim_DQL.csv")


################################################################################################
###                   Check for results that have > 1 Activity group                         ###
################################################################################################

res_act_dup_check <- res_act_grp %>%
  select(-ActivityID, -AG2AComment) %>%
  group_by(ResultID) %>%
  summarise(sum_actgrp_char = n())

act_dup_fix <- grade_prelim_DQL %>%
  left_join(res_act_dup_check, by = "ResultID") %>%
  group_by(ResultID) %>%
  #if resuly only has 1 activity group, use the prelim DQL
  #if result has > 1 activity and is not E, use the lowest tier
  #if result has > 1 activity and is E, use the second lowest tier
  mutate(fixed_DQL = ifelse(sum_actgrp_char == 1, prelim_DQL,
                            ifelse(
                              max(prelim_DQL != "E"),
                              sort(prelim_DQL, partial = sum_actgrp_char - 1)[sum_actgrp_char - 1],
                              max(prelim_DQL)
                            ))) %>%
  #pass fixed value back to prelim value
  mutate(prelim_DQL = fixed_DQL) %>%
  #collapse down for easier merging
  select(ResultID, actgrp_char, prelim_DQL) %>%
  #mutate(resactgrp = paste(ResultID, actgrp_char, sep = "-")) %>%
  select(ResultID, prelim_DQL) %>%
  distinct()


# Like 30 values come out as duplicates, when though they only have 1 actgrp_char.
# they all have an E tier and a B
# I can't figure it out, so here is a hack job just to set as the value that's not E 
kludge_fix_act_dup_fix <- act_dup_fix %>%
  group_by(ResultID) %>%
  mutate(num_res = n()) %>%
  mutate(prelim_DQL = ifelse(num_res == 1, prelim_DQL,
                            ifelse(
                              max(prelim_DQL != "E"),
                              sort(prelim_DQL, partial = num_res - 1)[num_res - 1],
                              max(prelim_DQL)
                            ))) %>%
  select(-num_res) %>%
  distinct()

act_dup_fix <- kludge_fix_act_dup_fix 
 
  
# Check work
# write.csv(act_dup_fix, file = "act_dup_fix.csv")



#merge "collapsed" reults back into table
preliminary_DQL <-  res_act  %>%
  left_join(act_dup_fix, by = "ResultID") 


# Check work
# write.csv(preliminary_DQL, file = "preliminary_DQL.csv")




#############################################################################
###                             Anomalies                                 ###
#############################################################################

#Create table that combines anomaly data with activity groups
res_anom = merge(preliminary_DQL, anom, by = "ResultID", all.x = TRUE)


# recode anomaly by type to get counts later - perhaps a better way to do this?
res_anom$AnomTypeCode = ifelse(res_anom$AnomalyType == "Highest99%AmbientValues" | res_anom$AnomalyType == "Lowest1%AmbientValues", "ambient_99",
                        ifelse(res_anom$AnomalyType == "Lowest5%SubmValues" | res_anom$AnomalyType == "Highest95%SubmValues" , "submit_95",
                        ifelse(res_anom$AnomalyType == "Lowest10%SubmValues" | res_anom$AnomalyType == "Highest90%SubmValues" , "submit_90",
                        ifelse(res_anom$AnomalyType == "Lowest5%SubmStnValues" | res_anom$AnomalyType == "Highest95%SubmStnValues" ,"station_95",
                        ifelse(res_anom$AnomalyType == "Lowest5%AmbientValues" | res_anom$AnomalyType == "Highest95%AmbientValues" ,"ambient_95",
                        ifelse(res_anom$AnomalyType == "OutOfRange" | res_anom$AnomalyType == "OverUpRange" ,"outofrange",      
                        ifelse(res_anom$AnomalyType == "BelowLOQ" ,"BelowLOQ", 
                        ifelse(res_anom$AnomalyType == "ViolatesLessProtectiveWQStandard" | res_anom$AnomalyType == "ViolatesWQStandard", "ViolateWQS",NA))))))))

#Create table that counts selected anomalies per resultID
# only counts anomalies that would trigger a review
anom_res_sum = res_anom %>%
  group_by(ResultID) %>%
  summarise(anom_sub_95 = sum(AnomTypeCode =="submit_95"),
            anom_amb_99 = sum(AnomTypeCode == "ambient_99"),
            anom_amb_95 = sum(AnomTypeCode == "ambient_95"),
            anom_WQS = sum(AnomTypeCode =="ViolateWQS"),
            anom_BelowLOQ = sum(AnomTypeCode =="BelowLOQ")) %>%
  replace(is.na(.), 0)
  

#if no anoms that would trigger review, set prelim_DQL to final_DQL
#This gets uploaded to access

#sets final DQL based on anomalies and % QC samples
anom_grade_totals <- preliminary_DQL %>%
  left_join(anom_res_sum, by = "ResultID") %>%
  mutate(final_DQL = ifelse(prelim_DQL < "C" & anom_amb_99 > 0, "Anom", 
                     ifelse(prelim_DQL < "C" & anom_sub_95 > 0 & anom_amb_95 >0, "Anom",
                     ifelse(prelim_DQL < "C" & anom_amb_95 > 0 & anom_WQS > 0, "Anom",
                     ifelse(prelim_DQL < "C" & anom_WQS > 0, "Anom", 
                     # > H in order to get prelim DQLs that start with QC %....
                     ifelse(prelim_DQL > "H", "Anom", prelim_DQL
                            )))))) %>%
  # add if "QC < X" then final_DQL = "Anom" 
  mutate(DQLCmt = "") %>%
  select(
    ResultID,
    ActivityID,
    CharID,
    StartDateTime,
    Result,
    RsltQual,
    StoretQual,
    Unit,
    QCorigDQL,
    DEQ_PREC,
    prelim_DQL,
    final_DQL,
    anom_sub_95,
    anom_amb_99,
    anom_amb_95,
    anom_WQS,
    anom_BelowLOQ,
    DQLCmt
  )


finalgradetotals <- anom_grade_totals %>%
  group_by(final_DQL) %>%
  summarise(n())



#check to see if successful
print(paste0("Number of results to grade: ",nrow(res)))
print(paste0("Number of results graded: ",nrow(anom_grade_totals)))
print(paste0("Percent successful: ", (nrow(res)/nrow(anom_grade_totals)*100)))


# This gets sent back to access for review and update
write.csv(anom_grade_totals, file = "grabdataforreview.csv", row.names = FALSE)




####################################################################################
### I don't remember why I wrote this review section. I am commenting out unless ### 
###                          we find out later we need it.                       ###
####################################################################################
# 
# # To calculate which actgrps have no anoms
# # Create table of results with their DQLs 
# DQLs <- anom_grade_totals %>%
#   select(ResultID,
#          final_DQL) %>%
#   right_join(res_act_grp, by = 'ResultID')
# 
# 
# # Summarise grades per Activity Group
# DQLs_actgrp <- DQLs %>%
#   group_by(ActGrpID) %>%
#   summarise(SubID = first(SubID),
#             sumA = sum(final_DQL == "A"),
#             sumB = sum(final_DQL == "B"),
#             sumC = sum(final_DQL == "C"),
#             sumE = sum(final_DQL == "E"),
#             sumAnom = sum(final_DQL == "Anom")) %>%
#   mutate(count = sumA + sumB + sumC + sumE + sumAnom) 
# 
# 
# 
# #Create table of activity Groups with no anomolies.
#  DQLs_actgrp_noanoms <- DQLs_actgrp %>%
#   filter(sumAnom == 0)
# 
#  # results table for activity groups with no anomolies
#  #Need to add in DQLs here
#  res_actgrp_no_anom <- DQLs_actgrp_noanoms %>%
#    mutate(no_anoms = "TRUE") %>%
#    select(ActGrpID, no_anoms) %>%
#    left_join(res_act_grp, by = "ActGrpID") %>%
#    select(-no_anoms)
#  
# 
#  # Summarise grades per Submission and find out percent that needs review
#  DQLs_sub_prct <- DQLs %>%
#   group_by(SubID) %>%
#   summarise( sumA = sum(final_DQL == "A"),
#              sumB = sum(final_DQL == "B"),
#              sumC = sum(final_DQL == "C"),
#              sumE = sum(final_DQL == "E"),
#              sumAnom = sum(final_DQL == "Anom")) %>%
#   mutate(count = sumA + sumB + sumC + sumE + sumAnom) %>% 
#   mutate(prct_anom = 100* sumAnom  / count )
#   
# 
#  #Write tables
#  write.csv(DQLs_sub_prct, file = "DQLs_sub_prct.csv")
#  write.csv(res_actgrp_no_anom, file = "res_actgrp_no_anom.csv" )


# To do:
# DONE - Figure out chronological method
# DONE - Check results that have >1 activity group and assign lowest DQL 
# DONE - check results for anomalies
# DONE - Assign final grades to non-anomalous results
# DONE - Flag Anomalous results
# DONE - Figure out how to display for review
# Add DQLs to  res_actgrp_no_anom
# create access update query to write Final DQLs to ORDEQ_DQL 







