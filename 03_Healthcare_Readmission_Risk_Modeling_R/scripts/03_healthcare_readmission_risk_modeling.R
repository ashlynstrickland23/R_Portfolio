# Healthcare Readmission Risk Modeling in R
# Project: 03_Healthcare_Readmission_Risk_Modeling_R

packages <- c("dplyr", "readr", "tibble", "caret", "randomForest", "rpart", "ggplot2")

installed_packages <- rownames(installed.packages())

for (pkg in packages) {
  if (!(pkg %in% installed_packages)) {
    install.packages(pkg)
  }
}

library(dplyr)
library(readr)
library(tibble)
library(caret)
library(randomForest)
library(rpart)
library(ggplot2)

dir.create("03_Healthcare_Readmission_Risk_Modeling_R/data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned", recursive = TRUE, showWarnings = FALSE)
dir.create("03_Healthcare_Readmission_Risk_Modeling_R/images", recursive = TRUE, showWarnings = FALSE)
dir.create("03_Healthcare_Readmission_Risk_Modeling_R/outputs", recursive = TRUE, showWarnings = FALSE)

set.seed(42)

num_patients <- 15000

patient_data <- tibble(
  patient_id = 1:num_patients,
  age = sample(18:90, num_patients, replace = TRUE),
  gender = sample(c("Female", "Male"), num_patients, replace = TRUE, prob = c(0.53, 0.47)),
  primary_diagnosis = sample(
    c("Heart Failure", "Diabetes", "COPD", "Pneumonia", "Kidney Disease", "Hypertension", "Post Surgery"),
    num_patients,
    replace = TRUE,
    prob = c(0.18, 0.17, 0.14, 0.13, 0.11, 0.15, 0.12)
  ),
  department = sample(
    c("Cardiology", "Internal Medicine", "Pulmonology", "Emergency", "Surgery", "Nephrology"),
    num_patients,
    replace = TRUE,
    prob = c(0.20, 0.25, 0.14, 0.16, 0.13, 0.12)
  ),
  length_of_stay_days = sample(1:21, num_patients, replace = TRUE),
  previous_admissions_12_months = rpois(num_patients, lambda = 1.4),
  emergency_visits_6_months = rpois(num_patients, lambda = 1.1),
  number_of_medications = sample(1:22, num_patients, replace = TRUE),
  number_of_chronic_conditions = sample(0:7, num_patients, replace = TRUE),
  discharge_disposition = sample(
    c("Home", "Home Health", "Skilled Nursing Facility", "Rehab", "Against Medical Advice"),
    num_patients,
    replace = TRUE,
    prob = c(0.58, 0.18, 0.12, 0.09, 0.03)
  ),
  follow_up_scheduled = sample(c("Yes", "No"), num_patients, replace = TRUE, prob = c(0.72, 0.28)),
  medication_adherence_score = round(pmin(pmax(rnorm(num_patients, mean = 72, sd = 18), 0), 100), 1),
  social_risk_score = round(pmin(pmax(rnorm(num_patients, mean = 42, sd = 22), 0), 100), 1),
  lab_risk_score = round(pmin(pmax(rnorm(num_patients, mean = 48, sd = 20), 0), 100), 1)
)

patient_data <- patient_data %>%
  mutate(
    age_band = case_when(
      age < 40 ~ "Under 40",
      age < 55 ~ "40 to 54",
      age < 70 ~ "55 to 69",
      TRUE ~ "70 Plus"
    ),
    chronic_condition_band = case_when(
      number_of_chronic_conditions <= 1 ~ "Low Comorbidity",
      number_of_chronic_conditions <= 3 ~ "Moderate Comorbidity",
      TRUE ~ "High Comorbidity"
    )
  )

patient_data <- patient_data %>%
  mutate(
    readmission_probability =
      0.06 +
      if_else(age >= 70, 0.08, 0) +
      if_else(primary_diagnosis == "Heart Failure", 0.13, 0) +
      if_else(primary_diagnosis == "COPD", 0.10, 0) +
      if_else(primary_diagnosis == "Kidney Disease", 0.09, 0) +
      if_else(length_of_stay_days >= 7, 0.08, 0) +
      if_else(previous_admissions_12_months >= 2, 0.13, 0) +
      if_else(emergency_visits_6_months >= 2, 0.10, 0) +
      if_else(number_of_medications >= 10, 0.08, 0) +
      if_else(number_of_chronic_conditions >= 4, 0.12, 0) +
      if_else(discharge_disposition == "Skilled Nursing Facility", 0.09, 0) +
      if_else(discharge_disposition == "Against Medical Advice", 0.18, 0) +
      if_else(follow_up_scheduled == "No", 0.11, 0) +
      if_else(medication_adherence_score < 55, 0.12, 0) +
      if_else(social_risk_score > 65, 0.10, 0) +
      if_else(lab_risk_score > 70, 0.09, 0) -
      if_else(follow_up_scheduled == "Yes", 0.03, 0) -
      if_else(medication_adherence_score >= 80, 0.04, 0),
    readmission_probability = pmin(pmax(readmission_probability, 0.01), 0.90),
    readmitted_30_days = rbinom(num_patients, size = 1, prob = readmission_probability),
    estimated_readmission_cost = if_else(
      readmitted_30_days == 1,
      round(runif(num_patients, min = 8500, max = 42000), 2),
      0
    ),
    prior_admission_risk_flag = if_else(previous_admissions_12_months >= 2, 1, 0),
    emergency_visit_risk_flag = if_else(emergency_visits_6_months >= 2, 1, 0),
    medication_risk_flag = if_else(number_of_medications >= 10, 1, 0),
    chronic_condition_risk_flag = if_else(number_of_chronic_conditions >= 4, 1, 0),
    follow_up_risk_flag = if_else(follow_up_scheduled == "No", 1, 0),
    adherence_risk_flag = if_else(medication_adherence_score < 55, 1, 0),
    social_risk_flag = if_else(social_risk_score > 65, 1, 0),
    lab_risk_flag = if_else(lab_risk_score > 70, 1, 0),
    total_risk_flags =
      prior_admission_risk_flag +
      emergency_visit_risk_flag +
      medication_risk_flag +
      chronic_condition_risk_flag +
      follow_up_risk_flag +
      adherence_risk_flag +
      social_risk_flag +
      lab_risk_flag,
    readmission_risk_band = case_when(
      readmission_probability < 0.15 ~ "Low Risk",
      readmission_probability < 0.30 ~ "Moderate Risk",
      readmission_probability < 0.50 ~ "High Risk",
      TRUE ~ "Critical Risk"
    ),
    care_management_recommendation = case_when(
      readmission_risk_band == "Critical Risk" ~ "Immediate Care Management Outreach",
      readmission_risk_band == "High Risk" ~ "High Priority Follow Up",
      readmission_risk_band == "Moderate Risk" ~ "Standard Follow Up",
      TRUE ~ "Routine Discharge Plan"
    )
  )

write_csv(
  patient_data,
  "03_Healthcare_Readmission_Risk_Modeling_R/data/raw/patient_readmission_15000_rows.csv"
)

diagnosis_summary <- patient_data %>%
  group_by(primary_diagnosis) %>%
  summarise(
    total_patients = n(),
    readmitted_patients = sum(readmitted_30_days),
    readmission_rate = round(mean(readmitted_30_days), 4),
    average_length_of_stay = round(mean(length_of_stay_days), 2),
    average_chronic_conditions = round(mean(number_of_chronic_conditions), 2),
    total_estimated_readmission_cost = round(sum(estimated_readmission_cost), 2),
    average_readmission_probability = round(mean(readmission_probability), 4),
    .groups = "drop"
  ) %>%
  arrange(desc(readmission_rate))

department_summary <- patient_data %>%
  group_by(department) %>%
  summarise(
    total_patients = n(),
    readmitted_patients = sum(readmitted_30_days),
    readmission_rate = round(mean(readmitted_30_days), 4),
    average_length_of_stay = round(mean(length_of_stay_days), 2),
    total_estimated_readmission_cost = round(sum(estimated_readmission_cost), 2),
    average_readmission_probability = round(mean(readmission_probability), 4),
    .groups = "drop"
  ) %>%
  arrange(desc(readmission_rate))

risk_band_summary <- patient_data %>%
  group_by(readmission_risk_band) %>%
  summarise(
    total_patients = n(),
    readmitted_patients = sum(readmitted_30_days),
    readmission_rate = round(mean(readmitted_30_days), 4),
    average_readmission_probability = round(mean(readmission_probability), 4),
    total_estimated_readmission_cost = round(sum(estimated_readmission_cost), 2),
    average_risk_flags = round(mean(total_risk_flags), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(average_readmission_probability))

care_management_summary <- patient_data %>%
  group_by(care_management_recommendation) %>%
  summarise(
    total_patients = n(),
    readmitted_patients = sum(readmitted_30_days),
    readmission_rate = round(mean(readmitted_30_days), 4),
    total_estimated_readmission_cost = round(sum(estimated_readmission_cost), 2),
    average_readmission_probability = round(mean(readmission_probability), 4),
    .groups = "drop"
  ) %>%
  arrange(desc(total_estimated_readmission_cost))

age_band_summary <- patient_data %>%
  group_by(age_band) %>%
  summarise(
    total_patients = n(),
    readmitted_patients = sum(readmitted_30_days),
    readmission_rate = round(mean(readmitted_30_days), 4),
    average_chronic_conditions = round(mean(number_of_chronic_conditions), 2),
    total_estimated_readmission_cost = round(sum(estimated_readmission_cost), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(readmission_rate))

write_csv(patient_data, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/patient_readmission_scored.csv")
write_csv(diagnosis_summary, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/diagnosis_readmission_summary.csv")
write_csv(department_summary, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/department_readmission_summary.csv")
write_csv(risk_band_summary, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/risk_band_summary.csv")
write_csv(care_management_summary, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/care_management_summary.csv")
write_csv(age_band_summary, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/age_band_summary.csv")

model_data <- patient_data %>%
  mutate(
    readmitted_30_days = factor(readmitted_30_days, levels = c(0, 1), labels = c("No", "Yes")),
    gender = as.factor(gender),
    primary_diagnosis = as.factor(primary_diagnosis),
    department = as.factor(department),
    discharge_disposition = as.factor(discharge_disposition),
    follow_up_scheduled = as.factor(follow_up_scheduled)
  )

train_index <- createDataPartition(model_data$readmitted_30_days, p = 0.75, list = FALSE)

train_data <- model_data[train_index, ]
test_data <- model_data[-train_index, ]

model_formula <- readmitted_30_days ~
  age +
  gender +
  primary_diagnosis +
  department +
  length_of_stay_days +
  previous_admissions_12_months +
  emergency_visits_6_months +
  number_of_medications +
  number_of_chronic_conditions +
  discharge_disposition +
  follow_up_scheduled +
  medication_adherence_score +
  social_risk_score +
  lab_risk_score +
  total_risk_flags

train_control <- trainControl(method = "none")

logistic_model <- train(
  model_formula,
  data = train_data,
  method = "glm",
  family = "binomial",
  trControl = train_control
)

tree_model <- train(
  model_formula,
  data = train_data,
  method = "rpart",
  trControl = train_control
)

forest_model <- randomForest(
  model_formula,
  data = train_data,
  ntree = 75,
  importance = TRUE
)

logistic_predictions <- predict(logistic_model, newdata = test_data)
tree_predictions <- predict(tree_model, newdata = test_data)
forest_predictions <- predict(forest_model, newdata = test_data)

logistic_confusion <- confusionMatrix(logistic_predictions, test_data$readmitted_30_days, positive = "Yes")
tree_confusion <- confusionMatrix(tree_predictions, test_data$readmitted_30_days, positive = "Yes")
forest_confusion <- confusionMatrix(forest_predictions, test_data$readmitted_30_days, positive = "Yes")

model_performance <- tibble(
  model = c("Logistic Regression", "Decision Tree", "Random Forest"),
  accuracy = c(
    logistic_confusion$overall["Accuracy"],
    tree_confusion$overall["Accuracy"],
    forest_confusion$overall["Accuracy"]
  ),
  sensitivity_recall = c(
    logistic_confusion$byClass["Sensitivity"],
    tree_confusion$byClass["Sensitivity"],
    forest_confusion$byClass["Sensitivity"]
  ),
  specificity = c(
    logistic_confusion$byClass["Specificity"],
    tree_confusion$byClass["Specificity"],
    forest_confusion$byClass["Specificity"]
  ),
  precision = c(
    logistic_confusion$byClass["Precision"],
    tree_confusion$byClass["Precision"],
    forest_confusion$byClass["Precision"]
  ),
  f1_score = c(
    logistic_confusion$byClass["F1"],
    tree_confusion$byClass["F1"],
    forest_confusion$byClass["F1"]
  )
) %>%
  mutate(across(where(is.numeric), ~ round(.x, 4))) %>%
  arrange(desc(f1_score))

best_model_name <- model_performance$model[1]

best_predictions <- if (best_model_name == "Logistic Regression") {
  logistic_predictions
} else if (best_model_name == "Decision Tree") {
  tree_predictions
} else {
  forest_predictions
}

best_confusion <- confusionMatrix(best_predictions, test_data$readmitted_30_days, positive = "Yes")

forest_probabilities <- predict(forest_model, newdata = model_data, type = "prob")[, "Yes"]

patient_data$predicted_readmission_probability <- forest_probabilities

patient_data <- patient_data %>%
  mutate(
    predicted_risk_band = case_when(
      predicted_readmission_probability < 0.15 ~ "Low Risk",
      predicted_readmission_probability < 0.30 ~ "Moderate Risk",
      predicted_readmission_probability < 0.50 ~ "High Risk",
      TRUE ~ "Critical Risk"
    )
  )

feature_importance <- importance(forest_model) %>%
  as.data.frame() %>%
  rownames_to_column("feature") %>%
  arrange(desc(MeanDecreaseGini)) %>%
  rename(Overall = MeanDecreaseGini)

write_csv(model_performance, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/model_performance_summary.csv")
write_csv(feature_importance, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/feature_importance.csv")
write_csv(patient_data, "03_Healthcare_Readmission_Risk_Modeling_R/data/cleaned/patient_readmission_scored.csv")

sink("03_Healthcare_Readmission_Risk_Modeling_R/outputs/confusion_matrix.txt")
print(paste("Best Model:", best_model_name))
print(best_confusion)
sink()

readmission_by_diagnosis_plot <- ggplot(diagnosis_summary, aes(x = reorder(primary_diagnosis, readmission_rate), y = readmission_rate)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Readmission Rate by Primary Diagnosis",
    x = "Primary Diagnosis",
    y = "Readmission Rate"
  ) +
  theme_minimal()

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/readmission_rate_by_diagnosis.png",
  readmission_by_diagnosis_plot,
  width = 10,
  height = 6,
  dpi = 300
)

readmission_by_department_plot <- ggplot(department_summary, aes(x = reorder(department, readmission_rate), y = readmission_rate)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Readmission Rate by Department",
    x = "Department",
    y = "Readmission Rate"
  ) +
  theme_minimal()

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/readmission_rate_by_department.png",
  readmission_by_department_plot,
  width = 10,
  height = 6,
  dpi = 300
)

cost_by_risk_band_plot <- ggplot(risk_band_summary, aes(x = readmission_risk_band, y = total_estimated_readmission_cost)) +
  geom_col() +
  labs(
    title = "Estimated Readmission Cost by Risk Band",
    x = "Risk Band",
    y = "Estimated Readmission Cost"
  ) +
  theme_minimal()

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/estimated_readmission_cost_by_risk_band.png",
  cost_by_risk_band_plot,
  width = 10,
  height = 6,
  dpi = 300
)

risk_distribution_plot <- ggplot(patient_data, aes(x = readmission_risk_band)) +
  geom_bar() +
  labs(
    title = "Patient Distribution by Readmission Risk Band",
    x = "Risk Band",
    y = "Patient Count"
  ) +
  theme_minimal()

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/patient_distribution_by_risk_band.png",
  risk_distribution_plot,
  width = 10,
  height = 6,
  dpi = 300
)

model_performance_plot <- ggplot(model_performance, aes(x = model, y = f1_score)) +
  geom_col() +
  labs(
    title = "Model Performance Comparison by F1 Score",
    x = "Model",
    y = "F1 Score"
  ) +
  theme_minimal()

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/model_performance_comparison.png",
  model_performance_plot,
  width = 10,
  height = 6,
  dpi = 300
)

feature_importance_plot <- feature_importance %>%
  slice_max(Overall, n = 15) %>%
  ggplot(aes(x = reorder(feature, Overall), y = Overall)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Top Readmission Risk Model Drivers",
    x = "Feature",
    y = "Importance"
  ) +
  theme_minimal()

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/feature_importance_readmission_risk.png",
  feature_importance_plot,
  width = 10,
  height = 6,
  dpi = 300
)

adherence_plot <- ggplot(
  patient_data,
  aes(x = medication_adherence_score, y = predicted_readmission_probability)
) +
  geom_point(alpha = 0.25) +
  labs(
    title = "Medication Adherence vs Predicted Readmission Probability",
    x = "Medication Adherence Score",
    y = "Predicted Readmission Probability"
  ) +
  theme_minimal()

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/adherence_vs_predicted_readmission.png",
  adherence_plot,
  width = 10,
  height = 6,
  dpi = 300
)

care_management_plot <- ggplot(care_management_summary, aes(x = care_management_recommendation, y = total_patients)) +
  geom_col() +
  labs(
    title = "Care Management Recommendation Summary",
    x = "Care Management Recommendation",
    y = "Patient Count"
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(
  "03_Healthcare_Readmission_Risk_Modeling_R/images/care_management_recommendation_summary.png",
  care_management_plot,
  width = 12,
  height = 6,
  dpi = 300
)

print("Healthcare readmission risk modeling project completed.")
print(paste("Rows created:", nrow(patient_data)))
print(paste("Readmission rate:", round(mean(patient_data$readmitted_30_days == 1) * 100, 2), "%"))
print(paste("Best model:", best_model_name))
print("Files saved to data, images, and outputs folders.")