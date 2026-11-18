@echo off
:: Check if Python is installed
where python >nul 2>nul
if %errorlevel% neq 0 (
    echo Python is not installed.
    exit /b 1
)

:: Check if pip is installed
where pip >nul 2>nul
if %errorlevel% neq 0 (
    echo pip is not installed.
    exit /b 1
)

:: Create a virtual environment
echo Creating virtual environment...
python -m venv venv

:: Activate the virtual environment
echo Activating virtual environment...
call venv\Scripts\activate.bat

:: Install requirements from requirements.txt
if exist requirements.txt (
    echo Installing dependencies from requirements.txt...
    pip install -r requirements.txt
) else (
    echo requirements.txt not found, skipping dependency installation.
)

echo Setup complete. Virtual environment is active.
