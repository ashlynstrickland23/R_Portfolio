# Customer Churn Analysis in R
# Project: 01_Customer_Churn_Analysis_R

packages <- c("dplyr", "readr", "tibble", "caret", "randomForest", "ggplot2")

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
library(ggplot2)

dir.create("01_Customer_Churn_Analysis_R/data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("01_Customer_Churn_Analysis_R/data/cleaned", recursive = TRUE, showWarnings = FALSE)
dir.create("01_Customer_Churn_Analysis_R/images", recursive = TRUE, showWarnings = FALSE)
dir.create("01_Customer_Churn_Analysis_R/outputs", recursive = TRUE, showWarnings = FALSE)

set.seed(42)

num_customers <- 10000

customer_data <- tibble(
  customer_id = 1:num_customers,
  customer_segment = sample(
    c("Small Business", "Mid Market", "Enterprise", "Consumer"),
    num_customers,
    replace = TRUE,
    prob = c(0.35, 0.30, 0.20, 0.15)
  ),
  contract_type = sample(
    c("Month to Month", "Annual", "Two Year"),
    num_customers,
    replace = TRUE,
    prob = c(0.50, 0.35, 0.15)
  ),
  region = sample(
    c("South", "West", "Midwest", "Northeast"),
    num_customers,
    replace = TRUE,
    prob = c(0.32, 0.27, 0.21, 0.20)
  ),
  tenure_months = sample(1:72, num_customers, replace = TRUE),
  monthly_revenue = round(pmax(rnorm(num_customers, mean = 185, sd = 65), 25), 2),
  support_tickets_last_90_days = rpois(num_customers, lambda = 2.2),
  late_payments_last_12_months = rpois(num_customers, lambda = 1.1),
  product_usage_score = round(pmin(pmax(rnorm(num_customers, mean = 68, sd = 18), 0), 100), 2),
  satisfaction_score = round(pmin(pmax(rnorm(num_customers, mean = 7.2, sd = 1.8), 1), 10), 1),
  last_login_days_ago = sample(0:120, num_customers, replace = TRUE),
  discount_percent = sample(
    c(0, 5, 10, 15, 20, 25),
    num_customers,
    replace = TRUE,
    prob = c(0.40, 0.20, 0.17, 0.12, 0.08, 0.03)
  )
)

customer_data <- customer_data %>%
  mutate(
    churn_probability =
      0.08 +
      if_else(contract_type == "Month to Month", 0.18, 0) +
      if_else(tenure_months < 12, 0.12, 0) +
      if_else(support_tickets_last_90_days >= 4, 0.10, 0) +
      if_else(late_payments_last_12_months >= 3, 0.08, 0) +
      if_else(product_usage_score < 45, 0.16, 0) +
      if_else(satisfaction_score < 6, 0.15, 0) +
      if_else(last_login_days_ago > 45, 0.12, 0) -
      if_else(contract_type == "Two Year", 0.08, 0) -
      if_else(tenure_months > 36, 0.06, 0),
    churn_probability = pmin(pmax(churn_probability, 0.02), 0.85),
    churned = rbinom(num_customers, size = 1, prob = churn_probability),
    annual_revenue = round(monthly_revenue * 12, 2),
    customer_lifetime_value = round(monthly_revenue * tenure_months, 2),
    revenue_at_risk = if_else(churned == 1, annual_revenue, 0),
    usage_risk_flag = if_else(product_usage_score < 45, 1, 0),
    satisfaction_risk_flag = if_else(satisfaction_score < 6, 1, 0),
    login_risk_flag = if_else(last_login_days_ago > 45, 1, 0),
    support_risk_flag = if_else(support_tickets_last_90_days >= 4, 1, 0),
    payment_risk_flag = if_else(late_payments_last_12_months >= 3, 1, 0),
    total_risk_flags =
      usage_risk_flag +
      satisfaction_risk_flag +
      login_risk_flag +
      support_risk_flag +
      payment_risk_flag,
    risk_band = case_when(
      churn_probability < 0.20 ~ "Low Risk",
      churn_probability < 0.40 ~ "Moderate Risk",
      churn_probability < 0.60 ~ "High Risk",
      TRUE ~ "Critical Risk"
    )
  )

write_csv(
  customer_data,
  "01_Customer_Churn_Analysis_R/data/raw/customer_churn_10000_rows.csv"
)

segment_summary <- customer_data %>%
  group_by(customer_segment) %>%
  summarise(
    total_customers = n(),
    churned_customers = sum(churned),
    churn_rate = round(mean(churned), 4),
    average_monthly_revenue = round(mean(monthly_revenue), 2),
    average_satisfaction_score = round(mean(satisfaction_score), 2),
    total_revenue_at_risk = round(sum(revenue_at_risk), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(churn_rate))

contract_summary <- customer_data %>%
  group_by(contract_type) %>%
  summarise(
    total_customers = n(),
    churned_customers = sum(churned),
    churn_rate = round(mean(churned), 4),
    average_monthly_revenue = round(mean(monthly_revenue), 2),
    average_tenure_months = round(mean(tenure_months), 2),
    total_revenue_at_risk = round(sum(revenue_at_risk), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(churn_rate))

risk_summary <- customer_data %>%
  group_by(risk_band) %>%
  summarise(
    total_customers = n(),
    churned_customers = sum(churned),
    churn_rate = round(mean(churned), 4),
    average_churn_probability = round(mean(churn_probability), 4),
    total_annual_revenue = round(sum(annual_revenue), 2),
    total_revenue_at_risk = round(sum(revenue_at_risk), 2),
    average_risk_flags = round(mean(total_risk_flags), 2),
    .groups = "drop"
  ) %>%
  arrange(desc(average_churn_probability))

write_csv(
  customer_data,
  "01_Customer_Churn_Analysis_R/data/cleaned/customer_churn_scored_dataset.csv"
)

write_csv(
  segment_summary,
  "01_Customer_Churn_Analysis_R/data/cleaned/segment_churn_summary.csv"
)

write_csv(
  contract_summary,
  "01_Customer_Churn_Analysis_R/data/cleaned/contract_churn_summary.csv"
)

write_csv(
  risk_summary,
  "01_Customer_Churn_Analysis_R/data/cleaned/risk_band_summary.csv"
)

churn_by_contract_plot <- ggplot(contract_summary, aes(x = contract_type, y = churn_rate)) +
  geom_col() +
  labs(
    title = "Churn Rate by Contract Type",
    x = "Contract Type",
    y = "Churn Rate"
  ) +
  theme_minimal()

ggsave(
  "01_Customer_Churn_Analysis_R/images/churn_rate_by_contract_type.png",
  churn_by_contract_plot,
  width = 10,
  height = 6,
  dpi = 300
)

churn_by_segment_plot <- ggplot(segment_summary, aes(x = customer_segment, y = churn_rate)) +
  geom_col() +
  labs(
    title = "Churn Rate by Customer Segment",
    x = "Customer Segment",
    y = "Churn Rate"
  ) +
  theme_minimal()

ggsave(
  "01_Customer_Churn_Analysis_R/images/churn_rate_by_customer_segment.png",
  churn_by_segment_plot,
  width = 10,
  height = 6,
  dpi = 300
)

revenue_at_risk_plot <- ggplot(risk_summary, aes(x = risk_band, y = total_revenue_at_risk)) +
  geom_col() +
  labs(
    title = "Revenue at Risk by Churn Risk Band",
    x = "Risk Band",
    y = "Revenue at Risk"
  ) +
  theme_minimal()

ggsave(
  "01_Customer_Churn_Analysis_R/images/revenue_at_risk_by_risk_band.png",
  revenue_at_risk_plot,
  width = 10,
  height = 6,
  dpi = 300
)

model_data <- customer_data %>%
  mutate(
    churned = factor(churned, levels = c(0, 1), labels = c("No", "Yes")),
    customer_segment = as.factor(customer_segment),
    contract_type = as.factor(contract_type),
    region = as.factor(region)
  )

train_index <- createDataPartition(model_data$churned, p = 0.75, list = FALSE)

train_data <- model_data[train_index, ]
test_data <- model_data[-train_index, ]

logistic_model <- train(
  churned ~ customer_segment +
    contract_type +
    region +
    tenure_months +
    monthly_revenue +
    support_tickets_last_90_days +
    late_payments_last_12_months +
    product_usage_score +
    satisfaction_score +
    last_login_days_ago +
    discount_percent +
    total_risk_flags,
  data = train_data,
  method = "glm",
  family = "binomial",
  trControl = trainControl(method = "none")
)

predictions <- predict(logistic_model, newdata = test_data)

confusion <- confusionMatrix(predictions, test_data$churned, positive = "Yes")

model_metrics <- tibble(
  model = "Logistic Regression",
  accuracy = round(confusion$overall["Accuracy"], 4),
  sensitivity_recall = round(confusion$byClass["Sensitivity"], 4),
  specificity = round(confusion$byClass["Specificity"], 4),
  precision = round(confusion$byClass["Precision"], 4),
  f1_score = round(confusion$byClass["F1"], 4)
)

write_csv(
  model_metrics,
  "01_Customer_Churn_Analysis_R/data/cleaned/model_performance_summary.csv"
)

sink("01_Customer_Churn_Analysis_R/outputs/model_confusion_matrix.txt")
print(confusion)
sink()

risk_distribution_plot <- ggplot(customer_data, aes(x = risk_band)) +
  geom_bar() +
  labs(
    title = "Customer Distribution by Risk Band",
    x = "Risk Band",
    y = "Customer Count"
  ) +
  theme_minimal()

ggsave(
  "01_Customer_Churn_Analysis_R/images/customer_distribution_by_risk_band.png",
  risk_distribution_plot,
  width = 10,
  height = 6,
  dpi = 300
)

usage_satisfaction_plot <- ggplot(
  customer_data,
  aes(x = product_usage_score, y = satisfaction_score, color = factor(churned))
) +
  geom_point(alpha = 0.35) +
  labs(
    title = "Product Usage vs Satisfaction by Churn Status",
    x = "Product Usage Score",
    y = "Satisfaction Score",
    color = "Churned"
  ) +
  theme_minimal()

ggsave(
  "01_Customer_Churn_Analysis_R/images/product_usage_vs_satisfaction_churn.png",
  usage_satisfaction_plot,
  width = 10,
  height = 6,
  dpi = 300
)

tenure_churn_plot <- ggplot(customer_data, aes(x = tenure_months, fill = factor(churned))) +
  geom_histogram(bins = 30, alpha = 0.75, position = "identity") +
  labs(
    title = "Customer Tenure Distribution by Churn Status",
    x = "Tenure Months",
    y = "Customer Count",
    fill = "Churned"
  ) +
  theme_minimal()

ggsave(
  "01_Customer_Churn_Analysis_R/images/tenure_distribution_by_churn_status.png",
  tenure_churn_plot,
  width = 10,
  height = 6,
  dpi = 300
)

risk_flags_plot <- customer_data %>%
  count(total_risk_flags) %>%
  ggplot(aes(x = total_risk_flags, y = n)) +
  geom_col() +
  labs(
    title = "Customer Count by Total Risk Flags",
    x = "Total Risk Flags",
    y = "Customer Count"
  ) +
  theme_minimal()

ggsave(
  "01_Customer_Churn_Analysis_R/images/customer_count_by_total_risk_flags.png",
  risk_flags_plot,
  width = 10,
  height = 6,
  dpi = 300
)

print("R customer churn analysis project completed.")
print(paste("Rows created:", nrow(customer_data)))
print(paste("Overall churn rate:", round(mean(customer_data$churned == 1) * 100, 2), "%"))
print("Files saved to data, images, and outputs folders.")