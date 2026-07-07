# Credit Risk Modeling and Loan Default Prediction in R
# Project: 02_Credit_Risk_Modeling_R

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

dir.create("02_Credit_Risk_Modeling_R/data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("02_Credit_Risk_Modeling_R/data/cleaned", recursive = TRUE, showWarnings = FALSE)
dir.create("02_Credit_Risk_Modeling_R/images", recursive = TRUE, showWarnings = FALSE)
dir.create("02_Credit_Risk_Modeling_R/outputs", recursive = TRUE, showWarnings = FALSE)

set.seed(42)

num_loans <- 25000

loan_data <- tibble(
  applicant_id = 1:num_loans,
  age = sample(21:72, num_loans, replace = TRUE),
  annual_income = round(pmax(rnorm(num_loans, mean = 78000, sd = 32000), 18000), 2),
  credit_score = round(pmin(pmax(rnorm(num_loans, mean = 680, sd = 75), 300), 850), 0),
  loan_amount = round(pmax(rnorm(num_loans, mean = 23500, sd = 12500), 1000), 2),
  employment_length_years = sample(0:30, num_loans, replace = TRUE),
  existing_debt = round(pmax(rnorm(num_loans, mean = 18000, sd = 14000), 0), 2),
  number_of_open_accounts = sample(1:18, num_loans, replace = TRUE),
  missed_payments_last_12_months = rpois(num_loans, lambda = 0.8),
  credit_utilization = round(pmin(pmax(rnorm(num_loans, mean = 0.42, sd = 0.22), 0), 1), 3),
  loan_purpose = sample(
    c("Debt Consolidation", "Home Improvement", "Medical", "Small Business", "Auto", "Personal"),
    num_loans,
    replace = TRUE,
    prob = c(0.34, 0.18, 0.10, 0.14, 0.12, 0.12)
  ),
  home_ownership = sample(
    c("Rent", "Mortgage", "Own"),
    num_loans,
    replace = TRUE,
    prob = c(0.42, 0.45, 0.13)
  )
)

loan_data <- loan_data %>%
  mutate(
    debt_to_income_ratio = round(existing_debt / annual_income, 3),
    loan_to_income_ratio = round(loan_amount / annual_income, 3),
    credit_score_band = case_when(
      credit_score < 580 ~ "Poor",
      credit_score < 670 ~ "Fair",
      credit_score < 740 ~ "Good",
      credit_score < 800 ~ "Very Good",
      TRUE ~ "Excellent"
    ),
    income_band = case_when(
      annual_income < 40000 ~ "Under 40K",
      annual_income < 75000 ~ "40K to 75K",
      annual_income < 120000 ~ "75K to 120K",
      TRUE ~ "120K Plus"
    )
  )

loan_data <- loan_data %>%
  mutate(
    default_probability =
      0.04 +
      if_else(credit_score < 580, 0.28, 0) +
      if_else(credit_score >= 580 & credit_score < 670, 0.14, 0) +
      if_else(debt_to_income_ratio > 0.45, 0.14, 0) +
      if_else(loan_to_income_ratio > 0.40, 0.10, 0) +
      if_else(missed_payments_last_12_months >= 2, 0.16, 0) +
      if_else(credit_utilization > 0.70, 0.12, 0) +
      if_else(employment_length_years < 2, 0.08, 0) +
      if_else(loan_purpose == "Small Business", 0.07, 0) +
      if_else(home_ownership == "Rent", 0.05, 0) -
      if_else(credit_score >= 740, 0.08, 0) -
      if_else(employment_length_years >= 10, 0.04, 0) -
      if_else(home_ownership == "Own", 0.03, 0),
    default_probability = pmin(pmax(default_probability, 0.01), 0.90),
    defaulted = rbinom(num_loans, size = 1, prob = default_probability),
    loan_value_at_risk = if_else(defaulted == 1, loan_amount, 0),
    dti_risk_flag = if_else(debt_to_income_ratio > 0.45, 1, 0),
    utilization_risk_flag = if_else(credit_utilization > 0.70, 1, 0),
    missed_payment_risk_flag = if_else(missed_payments_last_12_months >= 2, 1, 0),
    low_credit_score_flag = if_else(credit_score < 670, 1, 0),
    high_loan_to_income_flag = if_else(loan_to_income_ratio > 0.40, 1, 0),
    total_risk_flags =
      dti_risk_flag +
      utilization_risk_flag +
      missed_payment_risk_flag +
      low_credit_score_flag +
      high_loan_to_income_flag,
    risk_band = case_when(
      default_probability < 0.15 ~ "Low Risk",
      default_probability < 0.30 ~ "Moderate Risk",
      default_probability < 0.50 ~ "High Risk",
      TRUE ~ "Critical Risk"
    ),
    approval_recommendation = case_when(
      risk_band == "Low Risk" ~ "Approve",
      risk_band == "Moderate Risk" & loan_amount <= 30000 ~ "Approve with Review",
      risk_band == "Moderate Risk" ~ "Manual Underwriting Review",
      risk_band == "High Risk" ~ "High Risk Review",
      TRUE ~ "Decline or Require Strong Mitigation"
    )
  )

write_csv(
  loan_data,
  "02_Credit_Risk_Modeling_R/data/raw/loan_applicants_25000_rows.csv"
)

credit_score_summary <- loan_data %>%
  group_by(credit_score_band) %>%
  summarise(
    total_applicants = n(),
    defaulted_applicants = sum(defaulted),
    default_rate = round(mean(defaulted), 4),
    average_loan_amount = round(mean(loan_amount), 2),
    total_loan_value = round(sum(loan_amount), 2),
    loan_value_at_risk = round(sum(loan_value_at_risk), 2),
    average_default_probability = round(mean(default_probability), 4),
    .groups = "drop"
  ) %>%
  arrange(desc(default_rate))

income_band_summary <- loan_data %>%
  group_by(income_band) %>%
  summarise(
    total_applicants = n(),
    defaulted_applicants = sum(defaulted),
    default_rate = round(mean(defaulted), 4),
    average_income = round(mean(annual_income), 2),
    average_debt_to_income = round(mean(debt_to_income_ratio), 4),
    total_loan_value = round(sum(loan_amount), 2),
    loan_value_at_risk = round(sum(loan_value_at_risk), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(default_rate))

risk_band_summary <- loan_data %>%
  group_by(risk_band) %>%
  summarise(
    total_applicants = n(),
    defaulted_applicants = sum(defaulted),
    default_rate = round(mean(defaulted), 4),
    average_default_probability = round(mean(default_probability), 4),
    total_loan_value = round(sum(loan_amount), 2),
    loan_value_at_risk = round(sum(loan_value_at_risk), 2),
    average_risk_flags = round(mean(total_risk_flags), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(average_default_probability))

approval_summary <- loan_data %>%
  group_by(approval_recommendation) %>%
  summarise(
    total_applicants = n(),
    defaulted_applicants = sum(defaulted),
    default_rate = round(mean(defaulted), 4),
    total_loan_value = round(sum(loan_amount), 2),
    loan_value_at_risk = round(sum(loan_value_at_risk), 2),
    average_default_probability = round(mean(default_probability), 4),
    .groups = "drop"
  ) %>%
  arrange(desc(loan_value_at_risk))

write_csv(loan_data, "02_Credit_Risk_Modeling_R/data/cleaned/loan_applicants_scored.csv")
write_csv(credit_score_summary, "02_Credit_Risk_Modeling_R/data/cleaned/credit_score_summary.csv")
write_csv(income_band_summary, "02_Credit_Risk_Modeling_R/data/cleaned/income_band_summary.csv")
write_csv(risk_band_summary, "02_Credit_Risk_Modeling_R/data/cleaned/risk_band_summary.csv")
write_csv(approval_summary, "02_Credit_Risk_Modeling_R/data/cleaned/approval_recommendation_summary.csv")

model_data <- loan_data %>%
  mutate(
    defaulted = factor(defaulted, levels = c(0, 1), labels = c("No", "Yes")),
    loan_purpose = as.factor(loan_purpose),
    home_ownership = as.factor(home_ownership)
  )

train_index <- createDataPartition(model_data$defaulted, p = 0.75, list = FALSE)

train_data <- model_data[train_index, ]
test_data <- model_data[-train_index, ]

model_formula <- defaulted ~
  age +
  annual_income +
  credit_score +
  loan_amount +
  employment_length_years +
  existing_debt +
  number_of_open_accounts +
  missed_payments_last_12_months +
  credit_utilization +
  debt_to_income_ratio +
  loan_to_income_ratio +
  total_risk_flags +
  loan_purpose +
  home_ownership

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

logistic_confusion <- confusionMatrix(logistic_predictions, test_data$defaulted, positive = "Yes")
tree_confusion <- confusionMatrix(tree_predictions, test_data$defaulted, positive = "Yes")
forest_confusion <- confusionMatrix(forest_predictions, test_data$defaulted, positive = "Yes")

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

best_confusion <- confusionMatrix(best_predictions, test_data$defaulted, positive = "Yes")

forest_probabilities <- predict(forest_model, newdata = model_data, type = "prob")[, "Yes"]

loan_data$predicted_default_probability <- forest_probabilities

loan_data <- loan_data %>%
  mutate(
    predicted_risk_band = case_when(
      predicted_default_probability < 0.15 ~ "Low Risk",
      predicted_default_probability < 0.30 ~ "Moderate Risk",
      predicted_default_probability < 0.50 ~ "High Risk",
      TRUE ~ "Critical Risk"
    )
  )

feature_importance <- importance(forest_model) %>%
  as.data.frame() %>%
  rownames_to_column("feature") %>%
  arrange(desc(MeanDecreaseGini)) %>%
  rename(Overall = MeanDecreaseGini)

write_csv(model_performance, "02_Credit_Risk_Modeling_R/data/cleaned/model_performance_summary.csv")
write_csv(feature_importance, "02_Credit_Risk_Modeling_R/data/cleaned/feature_importance.csv")
write_csv(loan_data, "02_Credit_Risk_Modeling_R/data/cleaned/loan_applicants_scored.csv")

sink("02_Credit_Risk_Modeling_R/outputs/confusion_matrix.txt")
print(paste("Best Model:", best_model_name))
print(best_confusion)
sink()

default_by_credit_plot <- ggplot(credit_score_summary, aes(x = credit_score_band, y = default_rate)) +
  geom_col() +
  labs(
    title = "Default Rate by Credit Score Band",
    x = "Credit Score Band",
    y = "Default Rate"
  ) +
  theme_minimal()

ggsave(
  "02_Credit_Risk_Modeling_R/images/default_rate_by_credit_score_band.png",
  default_by_credit_plot,
  width = 10,
  height = 6,
  dpi = 300
)

default_by_income_plot <- ggplot(income_band_summary, aes(x = income_band, y = default_rate)) +
  geom_col() +
  labs(
    title = "Default Rate by Income Band",
    x = "Income Band",
    y = "Default Rate"
  ) +
  theme_minimal()

ggsave(
  "02_Credit_Risk_Modeling_R/images/default_rate_by_income_band.png",
  default_by_income_plot,
  width = 10,
  height = 6,
  dpi = 300
)

loan_value_at_risk_plot <- ggplot(risk_band_summary, aes(x = risk_band, y = loan_value_at_risk)) +
  geom_col() +
  labs(
    title = "Loan Value at Risk by Credit Risk Band",
    x = "Risk Band",
    y = "Loan Value at Risk"
  ) +
  theme_minimal()

ggsave(
  "02_Credit_Risk_Modeling_R/images/loan_value_at_risk_by_risk_band.png",
  loan_value_at_risk_plot,
  width = 10,
  height = 6,
  dpi = 300
)

risk_distribution_plot <- ggplot(loan_data, aes(x = risk_band)) +
  geom_bar() +
  labs(
    title = "Applicant Distribution by Risk Band",
    x = "Risk Band",
    y = "Applicant Count"
  ) +
  theme_minimal()

ggsave(
  "02_Credit_Risk_Modeling_R/images/credit_risk_distribution.png",
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
  "02_Credit_Risk_Modeling_R/images/model_performance_comparison.png",
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
    title = "Top Credit Risk Model Drivers",
    x = "Feature",
    y = "Importance"
  ) +
  theme_minimal()

ggsave(
  "02_Credit_Risk_Modeling_R/images/feature_importance_credit_risk.png",
  feature_importance_plot,
  width = 10,
  height = 6,
  dpi = 300
)

dti_default_plot <- ggplot(
  loan_data,
  aes(x = debt_to_income_ratio, y = predicted_default_probability)
) +
  geom_point(alpha = 0.25) +
  labs(
    title = "Debt to Income Ratio vs Predicted Default Probability",
    x = "Debt to Income Ratio",
    y = "Predicted Default Probability"
  ) +
  theme_minimal()

ggsave(
  "02_Credit_Risk_Modeling_R/images/debt_to_income_vs_default.png",
  dti_default_plot,
  width = 10,
  height = 6,
  dpi = 300
)

approval_plot <- ggplot(approval_summary, aes(x = approval_recommendation, y = total_applicants)) +
  geom_col() +
  labs(
    title = "Approval Recommendation Summary",
    x = "Approval Recommendation",
    y = "Applicant Count"
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(
  "02_Credit_Risk_Modeling_R/images/approval_recommendation_summary.png",
  approval_plot,
  width = 12,
  height = 6,
  dpi = 300
)

print("Credit risk modeling project completed.")
print(paste("Rows created:", nrow(loan_data)))
print(paste("Default rate:", round(mean(loan_data$defaulted == 1) * 100, 2), "%"))
print(paste("Best model:", best_model_name))
print("Files saved to data, images, and outputs folders.")