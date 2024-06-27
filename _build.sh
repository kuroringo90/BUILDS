#!/bin/bash

source _utils.sh
source ._env # remove this line if you want environment variables to be set in the shell or use a different method to set them

# Check if required variables are set
req_vars=("DEVICE" "ROM_NAME" "ZIP_NAME" "GIT_NAME" "RCLONE_REMOTE" "GIT_EMAIL" "REPOS_JSON" "SYNC_SOURCE_COMMAND" "RELEASE_GITHUB_TOKEN" "GITHUB_RELEASE_REPO" "RELEASE_OUT_DIR" "RELEASE_FILES_PATTERN")
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
 
    # Build GApps
    # if BUILD_GAPPS_COMMAND is set, otherwise skip
    if [ -n "$BUILD_GAPPS_COMMAND" ]; then
        start_time_gapps=$(date +%s)
        logt "Building GApps..."
        eval "$BUILD_GAPPS_COMMAND"
        build_status=$?
        
        if [ $build_status -ne 0 ]; then
            logt "GApps build failed. Aborting."
            telegram_send_file "out/error.log" "GApps build log"
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
    


logt "Uploading."
# Remove SomethingOS file
rm -f ./$ZIP_NAME-*-vayu-*-signed-target_files-eng.nobody.zip

gapps_file=$(ls ./$ZIP_NAME-*.zip | head -n 1)

upload_with_rclone "$gapps_file" 
if [ $? -ne 0 ]; then
  logt "Gapps upload failed."
  exit 1  
fi

end_time=$(date +%s)
# convert seconds to hours, minutes, and seconds
time_taken=$(compute_build_time "$start_time" "$end_time")
telegram_send_message "Total time taken *$time_taken*"
echo "Total time taken $time_taken"

logt "Build finished."

