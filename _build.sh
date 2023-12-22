#!/bin/bash

source _utils.sh
source ._env # remove this line if you want environment variables to be set in the shell or use a different method to set them

# Check if required variables are set
req_vars=("DEVICE" "ROM_NAME" "ZIP_NAME" "GIT_NAME" "RCLONE_REMOTE" "GIT_EMAIL" "REPOS_JSON" "BUILD_INSTALL_CLEAN" "SYNC_SOURCE_COMMAND" "RELEASE_GITHUB_TOKEN" "GITHUB_RELEASE_REPO" "RELEASE_OUT_DIR" "RELEASE_FILES_PATTERN")
for var in "${req_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Required variable $var is not set. Please set it in ._env"
        exit 1
    fi
done

#telegram_send_message "⏳"
telegram_send_message "*Build Initiated*: [$ROM_NAME for $DEVICE]($GITHUB_RUN_URL)" true

# Check either BUILD_VANILLA_COMMAND or BUILD_GAPPS_COMMAND is set
if [ -z "$BUILD_VANILLA_COMMAND" ] && [ -z "$BUILD_GAPPS_COMMAND" ]; then
    logt "Either BUILD_VANILLA_COMMAND or BUILD_GAPPS_COMMAND is not set. Please set it in ._env"
    exit 1
fi

start_time=$(date +%s)

# Sync source
if [[ "$SYNC_FLAG" == "true" ]]; then
    logt "Syncing source..."
    start_time_sync=$(date +%s)
    eval "${SYNC_SOURCE_COMMAND}" | tee sync_source.log
    if [ $? -ne 0 ]; then
        echo "Sync failed. Aborting."
        telegram_send_message "Sync failed. Aborting."
        telegram_send_file sync_source.log "Sync source log"
        exit 1
    fi
    end_time_sync=$(date +%s)
    sync_time_taken=$(compute_build_time "$start_time_sync" "$end_time_sync")
    logt "Sync completed in $sync_time_taken"
fi

# Make install clean to clean old zips
logt "Cleaning Up..."
    if [ -e "out/target/product/$DEVICE/$ZIP_NAME"* ]; then
        eval "$BUILD_INSTALL_CLEAN"
        if [ $? -ne 0 ]; then
            echo "Install clean failed. Aborting."
            telegram_send_message "Install clean failed. Aborting."
            exit 1
        fi
    else
        echo "No zip found. Skipping install clean."
        telegram_send_message "No zip found. Skipping install clean."
    fi
 
# Build GApps
# if BUILD_GAPPS_COMMAND is set, otherwise skip
if [ -n "$BUILD_GAPPS_COMMAND" ]; then
    start_time_gapps=$(date +%s)
    gapps_log_file="gapps_build.log"
    logt "Building GApps..."
    # if LOG_OUTPUT is set to false, then don't log output
 if [ "$LOG_OUTPUT" == "false" ]; then
    eval "$BUILD_GAPPS_COMMAND"
    build_status=$?
      else
    eval "$BUILD_GAPPS_COMMAND" | tee "$gapps_log_file"
    build_status=${PIPESTATUS[0]}
fi

if [ $build_status -ne 0 ]; then
    logt "GApps build failed. Aborting."
    telegram_send_file "$gapps_log_file" "GApps build log"
    exit 1
fi
    end_time_gapps=$(date +%s)
    gapps_time_taken=$(compute_build_time "$start_time_gapps" "$end_time_gapps")
    logt "GApps build completed in $gapps_time_taken"
    remove_ota_package # remove OTA package if present
    if [ $? -ne 0 ]; then
        logt "Failed to remove OTA package. Aborting."
        exit 1
    fi
else
    echo "BUILD_GAPPS_COMMAND is not set. Skipping GApps build."
fi

# Build Vanilla
# if BUILD_VANILLA_COMMAND is set, otherwise skip
if [ -n "$BUILD_VANILLA_COMMAND" ]; then
    start_time_vanilla=$(date +%s)
    vanilla_log_file="vanilla_build.log"
    logt "Building vanilla..."
    # if LOG_OUTPUT is set to false, then don't log output
if [ "$LOG_OUTPUT" == "false" ]; then
    eval "$BUILD_VANILLA_COMMAND"
    build_status=$?
else
    eval "$BUILD_VANILLA_COMMAND" | tee "$vanilla_log_file"
    build_status=${PIPESTATUS[0]}
fi

if [ $build_status -ne 0 ]; then
    logt "Vanilla build failed. Aborting."
    telegram_send_file "$vanilla_log_file" "Vanilla build log"
    exit 1
fi
    end_time_vanilla=$(date +%s)
    vanilla_time_taken=$(compute_build_time "$start_time_vanilla" "$end_time_vanilla")
    logt "Vanilla build completed in $vanilla_time_taken"
    remove_ota_package # remove OTA package if present
    if [ $? -ne 0 ]; then
        logt "Failed to remove OTA package. Aborting."
        exit 1
    fi
else
    echo "BUILD_VANILLA_COMMAND is not set. Skipping vanilla build."
fi


logt "Uploading."

gapps_file=$(ls out/target/product/$DEVICE/$ZIP_NAME-*-GAPPS-*.zip | head -n 1)

upload_with_rclone "$gapps_file" 
if [ $? -ne 0 ]; then
  logt "Gapps upload failed."
  exit 1  
fi

vanilla_file=$(ls out/target/product/$DEVICE/$ZIP_NAME-*-VANILLA-*.zip 2> /dev/null)

if [ -n "$vanilla_file" ]; then
  upload_with_rclone "$vanilla_file"
  if [ $? -ne 0 ]; then
    logt "Vanilla upload failed."
    exit 1
  fi  
else
  logt "No vanilla ZIP to upload."  
fi

end_time=$(date +%s)
# convert seconds to hours, minutes, and seconds
time_taken=$(compute_build_time "$start_time" "$end_time")
telegram_send_message "Total time taken *$time_taken*"
echo "Total time taken $time_taken"

logt "Build finished."

