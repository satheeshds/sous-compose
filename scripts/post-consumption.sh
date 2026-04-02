#!/usr/bin/env bash

echo "

A document with an id of ${DOCUMENT_ID} was just consumed.  I know the
following additional information about it:

* Generated File Name: ${DOCUMENT_FILE_NAME}
* Document type: ${DOCUMENT_TYPE}
* Archive Path: ${DOCUMENT_ARCHIVE_PATH}
* Source Path: ${webwebhookDOCUMENT_SOURCE_PATH}
* Created: ${DOCUMENT_CREATED}
* Added: ${DOCUMENT_ADDED}
* Modified: ${DOCUMENT_MODIFIED}
* Thumbnail Path: ${DOCUMENT_THUMBNAIL_PATH}
* Download URL: ${DOCUMENT_DOWNLOAD_URL}
* Thumbnail URL: ${DOCUMENT_THUMBNAIL_URL}
* Owner Name: ${DOCUMENT_OWNER}
* Correspondent: ${DOCUMENT_CORRESPONDENT}
* Tags: ${DOCUMENT_TAGS}

It was consumed with the passphrase ${PASSPHRASE}

"
# check if the document type is Bill
if [[ "${DOCUMENT_TYPE,,}" == "bill" ]]; then
    echo "Document type is 'bill' - triggering invoice processor..."
    
    json_payload="{\"id\": ${DOCUMENT_ID}}"
    # Call the document-processor service
    # curl -X POST "http://document-processor:80/webhook/${DOCUMENT_ID}" \
    #     -H "Content-Type: application/json" \
    #     -d "$json_payload" \
    #     --max-time 30 \
    #     --fail-with-body || echo "Failed to trigger invoice processor"
    
    echo "Invoice processor triggered for document ${DOCUMENT_ID}"
fi