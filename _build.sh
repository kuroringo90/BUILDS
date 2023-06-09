#!/bin/bash

source _utils.sh
source ._env # remove this line if you want environment variables to be set in the shell or use a different method to set them

# Check if required variables are set
req_vars=("DEVICE" "ROM_NAME" "GIT_NAME" "GIT_EMAIL" "REPOS_JSON"  "SYNC_SOURCE_COMMAND" "RELEASE_GITHUB_TOKEN" "GITHUB_RELEASE_REPO" "RELEASE_OUT_DIR" "RELEASE_FILES_PATTERN")
for var in "${req_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Required variable $var is not set. Please set it in ._env"
        exit 1
    fi
done

telegram_send_message "⏳"
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

# Clean strategy
logt "Clean Strategy..."
# Check if CLEAN is set to "installclean"
if [[ "$CLEAN" == "installclean" ]]; then
    telegram_send_message "Make Installclean"
    source build/envsetup.sh && lunch lineage_vayu-userdebug && make installclean
    if [ $? -ne 0 ]; then
        telegram_send_message "Install Clean Failed. Aborting."
        exit 1
    fi
# Check if CLEAN is set to "clobber"
elif [[ "$CLEAN" == "clobber" ]]; then
    telegram_send_message "Clobber"
    source build/envsetup.sh && lunch lineage_vayu-userdebug && make clobber
    if [ $? -ne 0 ]; then
        telegram_send_message "Clobber Failed. Aborting."
        exit 1
    fi
# Check if CLEAN is set to "nope"
elif [[ "$CLEAN" == "nope" ]]; then
    telegram_send_message "DIRTY BUILD"
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

# Release builds
#tag=$(date +'v%d-%m-%Y-%H%M')
#(github_release --token $RELEASE_GITHUB_TOKEN --repo $GITHUB_RELEASE_REPO --tag $tag --pattern $RELEASE_FILES_PATTERN)

# Function to upload file to Pixeldrain
upload_to_pixeldrain() {
    MINPARAMS=1
    PDSERVER="https://pixeldrain.com"

    for FILE in "$@"
    do
        FILENAME="$(basename "$FILE")"

        echo "Uploading $FILENAME ..."
        RESPONSE=$(curl -# -F "name=$FILENAME" -F "file=@$FILE" $PDSERVER/api/file)
        FILEID=$(echo $RESPONSE | grep -Po '(?<="id":")[^"]*')

        FILE_URL="$PDSERVER/u/$FILEID"
        echo "Uploaded $FILENAME - Your file URL: $FILE_URL"
        telegram_send_message "PixelDrain: [$FILENAME]($FILE_URL)" true
        echo ""
    done
}

logt "Uploading."
target_file=$(ls out/target/product/vayu/risingOS*.zip* | head -n 1)
upload_to_pixeldrain "$target_file"

if [ $? -ne 0 ]; then
    logt "Upload failed."
    exit 1
fi



end_time=$(date +%s)
# convert seconds to hours, minutes, and seconds
time_taken=$(compute_build_time "$start_time" "$end_time")
telegram_send_message "Total time taken *$time_taken*"
echo "Total time taken $time_taken"

logt "Build finished."

