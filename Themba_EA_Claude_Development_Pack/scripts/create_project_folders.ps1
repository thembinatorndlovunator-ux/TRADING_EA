$Root = "C:\TradingProjects\Themba_EA_Improvement_Lab"

$Folders = @(
    "01_BASELINE\EA_V637",
    "01_BASELINE\EA_V811",
    "01_BASELINE\setfiles",
    "01_BASELINE\indicators",
    "01_BASELINE\backtests",
    "01_BASELINE\logs",
    "01_BASELINE\screenshots",
    "02_STRATEGY_KNOWLEDGE\raw_materials",
    "02_STRATEGY_KNOWLEDGE\extracted_rules",
    "02_STRATEGY_KNOWLEDGE\approved_rules",
    "02_STRATEGY_KNOWLEDGE\visual_examples",
    "03_SOURCE_CODE\MQL5\Experts",
    "03_SOURCE_CODE\MQL5\Include\ThembaEA",
    "03_SOURCE_CODE\Python\analysis",
    "03_SOURCE_CODE\Python\data_collection",
    "03_SOURCE_CODE\Python\news_connectors",
    "04_NEWS_SYSTEM\raw",
    "04_NEWS_SYSTEM\normalized",
    "04_NEWS_SYSTEM\historical",
    "04_NEWS_SYSTEM\cache",
    "04_NEWS_SYSTEM\logs",
    "05_WEB_RESEARCH\research_requests",
    "05_WEB_RESEARCH\pending_review",
    "05_WEB_RESEARCH\approved_research",
    "05_WEB_RESEARCH\rejected_research",
    "06_MARKET_DATA\metals",
    "06_MARKET_DATA\synthetic_indices",
    "06_MARKET_DATA\symbol_specifications",
    "07_TESTING\regression_tests",
    "07_TESTING\visual_tests",
    "07_TESTING\in_sample",
    "07_TESTING\out_of_sample",
    "07_TESTING\walk_forward",
    "07_TESTING\monte_carlo",
    "07_TESTING\stress_tests",
    "07_TESTING\news_tests",
    "08_RESULTS\trade_exports",
    "08_RESULTS\backtest_reports",
    "08_RESULTS\forward_test_reports",
    "08_RESULTS\python_reports",
    "08_RESULTS\screenshot_analysis",
    "09_HANDOVERS\claude_to_codex",
    "09_HANDOVERS\codex_to_claude",
    "09_HANDOVERS\claude_to_chatgpt",
    "09_HANDOVERS\chatgpt_to_claude",
    "10_RELEASES\development",
    "10_RELEASES\demo_approved",
    "10_RELEASES\live_approved",
    "10_RELEASES\retired",
    "scripts",
    "secrets"
)

New-Item -ItemType Directory -Path $Root -Force | Out-Null

foreach ($Folder in $Folders) {
    New-Item -ItemType Directory -Path (Join-Path $Root $Folder) -Force | Out-Null
}

Write-Host "Project folders are ready at $Root"
