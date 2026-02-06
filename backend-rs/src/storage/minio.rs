use aws_config::Region;
use aws_sdk_s3::{
    config::Credentials,
    primitives::ByteStream,
    types::{BucketCannedAcl, ObjectCannedAcl},
    Client, Config,
};
use bytes::Bytes;

use crate::{config::MinioConfig, error::AppResult};

#[derive(Clone)]
pub struct MinioClient {
    client: Client,
    config: MinioConfig,
}

impl MinioClient {
    pub async fn new(config: &MinioConfig) -> AppResult<Self> {
        let creds = Credentials::new(
            &config.access_key,
            &config.secret_key,
            None,
            None,
            "minio",
        );

        let s3_config = Config::builder()
            .region(Region::new(config.region.clone()))
            .endpoint_url(&config.endpoint)
            .credentials_provider(creds)
            .force_path_style(true)
            .build();

        let client = Client::from_conf(s3_config);

        Ok(Self {
            client,
            config: config.clone(),
        })
    }

    pub async fn ensure_buckets(&self) -> AppResult<()> {
        let buckets = [
            &self.config.stickers_bucket,
            &self.config.avatars_bucket,
            &self.config.attachments_bucket,
        ];

        for bucket in buckets {
            self.create_bucket_if_not_exists(bucket).await?;
        }

        Ok(())
    }

    async fn create_bucket_if_not_exists(&self, bucket: &str) -> AppResult<()> {
        let result = self.client.head_bucket().bucket(bucket).send().await;

        if result.is_err() {
            self.client
                .create_bucket()
                .bucket(bucket)
                .acl(BucketCannedAcl::PublicRead)
                .send()
                .await
                .map_err(|e| anyhow::anyhow!("Failed to create bucket: {}", e))?;
            tracing::info!("Created bucket: {}", bucket);
        }

        Ok(())
    }

    pub async fn upload_file(
        &self,
        bucket: &str,
        key: &str,
        data: Bytes,
        content_type: &str,
    ) -> AppResult<String> {
        self.client
            .put_object()
            .bucket(bucket)
            .key(key)
            .body(ByteStream::from(data))
            .content_type(content_type)
            .acl(ObjectCannedAcl::PublicRead)
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("Failed to upload file: {}", e))?;

        Ok(self.get_file_url(bucket, key))
    }

    pub async fn download_file(&self, bucket: &str, key: &str) -> AppResult<Bytes> {
        let result = self
            .client
            .get_object()
            .bucket(bucket)
            .key(key)
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("Failed to download file: {}", e))?;

        let data = result
            .body
            .collect()
            .await
            .map_err(|e| anyhow::anyhow!("Failed to read file body: {}", e))?;

        Ok(data.into_bytes())
    }

    pub async fn delete_file(&self, bucket: &str, key: &str) -> AppResult<()> {
        self.client
            .delete_object()
            .bucket(bucket)
            .key(key)
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("Failed to delete file: {}", e))?;

        Ok(())
    }

    pub async fn file_exists(&self, bucket: &str, key: &str) -> AppResult<bool> {
        let result = self.client.head_object().bucket(bucket).key(key).send().await;

        Ok(result.is_ok())
    }

    pub fn get_file_url(&self, bucket: &str, key: &str) -> String {
        match &self.config.public_url {
            Some(public_url) => format!("{}/{}/{}", public_url, bucket, key),
            None => format!("{}/{}/{}", self.config.endpoint, bucket, key),
        }
    }

    pub async fn list_files(&self, bucket: &str, prefix: &str) -> AppResult<Vec<String>> {
        let result = self
            .client
            .list_objects_v2()
            .bucket(bucket)
            .prefix(prefix)
            .send()
            .await
            .map_err(|e| anyhow::anyhow!("Failed to list files: {}", e))?;

        let keys: Vec<String> = result
            .contents()
            .iter()
            .filter_map(|obj| obj.key().map(|k| k.to_string()))
            .collect();

        Ok(keys)
    }

    // Bucket accessors
    pub fn stickers_bucket(&self) -> &str {
        &self.config.stickers_bucket
    }

    pub fn avatars_bucket(&self) -> &str {
        &self.config.avatars_bucket
    }

    pub fn attachments_bucket(&self) -> &str {
        &self.config.attachments_bucket
    }
}
