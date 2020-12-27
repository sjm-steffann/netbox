#!/bin/bash
# This script will prepare NetBox to run after the code has been upgraded to
# its most recent release.

cd "$(dirname "$0")"
VIRTUALENV="$(pwd -P)/venv"

# If PYTHON hasn't been set by the user perform auto-detection
if [ -z "$PYTHON" ]; then
  TRY_VERSIONS="
    /usr/local/bin/python3.9
    /usr/bin/python3.9
    /usr/local/bin/python3.8
    /usr/bin/python3.8
    /usr/local/bin/python3.7
    /usr/bin/python3.7
    /usr/local/bin/python3.6
    /usr/bin/python3.6
    /usr/local/bin/python3
    /usr/bin/python3
  "

  for python in $TRY_VERSIONS; do
    if [ -x "$python" ] && $python -c "import sys; import venv; sys.exit(0 if sys.version_info >= (3,6) else 1)"; then
      PYTHON="$python"
      break
    fi
  done

  if [ -z "$PYTHON" ]; then
    echo "--------------------------------------------------------------------"
    echo "ERROR: Failed to find a supported Python interpreter. Python 3.6 or"
    echo "higher is required. Check that you have the required system packages"
    echo "installed."
    echo "--------------------------------------------------------------------"
    exit 1
  else
    echo "Using $PYTHON"
  fi
fi

# Remove the existing virtual environment (if any)
if [ -d "$VIRTUALENV" ]; then
  COMMAND="rm -rf ${VIRTUALENV}"
  echo "Removing old virtual environment..."
  eval $COMMAND
else
  WARN_MISSING_VENV=1
fi

# Create a new virtual environment
COMMAND="$PYTHON -m venv ${VIRTUALENV}"
echo "Creating a new virtual environment at ${VIRTUALENV}..."
eval $COMMAND || {
  echo "--------------------------------------------------------------------"
  echo "ERROR: Failed to create the virtual environment. Check that you have"
  echo "the required system packages installed and the following path is"
  echo "writable: ${VIRTUALENV}"
  echo "--------------------------------------------------------------------"
  exit 1
}

# Activate the virtual environment
source "${VIRTUALENV}/bin/activate"

# Install necessary system packages
COMMAND="pip3 install wheel"
echo "Installing Python system packages ($COMMAND)..."
eval $COMMAND || exit 1

# Install required Python packages
COMMAND="pip3 install -r requirements.txt"
echo "Installing core dependencies ($COMMAND)..."
eval $COMMAND || exit 1

# Install optional packages (if any)
if [ -s "local_requirements.txt" ]; then
  COMMAND="pip3 install -r local_requirements.txt"
  echo "Installing local dependencies ($COMMAND)..."
  eval $COMMAND || exit 1
elif [ -f "local_requirements.txt" ]; then
  echo "Skipping local dependencies (local_requirements.txt is empty)"
else
  echo "Skipping local dependencies (local_requirements.txt not found)"
fi

# Apply any database migrations
COMMAND="python3 netbox/manage.py migrate"
echo "Applying database migrations ($COMMAND)..."
eval $COMMAND || exit 1

# Trace any missing cable paths (not typically needed)
COMMAND="python3 netbox/manage.py trace_paths --no-input"
echo "Checking for missing cable paths ($COMMAND)..."
eval $COMMAND || exit 1

# Collect static files
COMMAND="python3 netbox/manage.py collectstatic --no-input"
echo "Collecting static files ($COMMAND)..."
eval $COMMAND || exit 1

# Delete any stale content types
COMMAND="python3 netbox/manage.py remove_stale_contenttypes --no-input"
echo "Removing stale content types ($COMMAND)..."
eval $COMMAND || exit 1

# Delete any expired user sessions
COMMAND="python3 netbox/manage.py clearsessions"
echo "Removing expired user sessions ($COMMAND)..."
eval $COMMAND || exit 1

# Clear all cached data
COMMAND="python3 netbox/manage.py invalidate all"
echo "Clearing cache data ($COMMAND)..."
eval $COMMAND || exit 1

if [ -v WARN_MISSING_VENV ]; then
  echo "--------------------------------------------------------------------"
  echo "WARNING: No existing virtual environment was detected. A new one has"
  echo "been created. Update your systemd service files to reflect the new"
  echo "Python and gunicorn executables. (If this is a new installation,"
  echo "this warning can be ignored.)"
  echo ""
  echo "netbox.service ExecStart:"
  echo "  ${VIRTUALENV}/bin/gunicorn"
  echo ""
  echo "netbox-rq.service ExecStart:"
  echo "  ${VIRTUALENV}/bin/python"
  echo ""
  echo "After modifying these files, reload the systemctl daemon:"
  echo "  > systemctl daemon-reload"
  echo "--------------------------------------------------------------------"
fi

echo "Upgrade complete! Don't forget to restart the NetBox services:"
echo "  > sudo systemctl restart netbox netbox-rq"
