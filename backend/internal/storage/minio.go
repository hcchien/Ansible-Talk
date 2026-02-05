package storage

import (
	"context"
	"fmt"
	"io"
	"net/url"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"

	"github.com/ansible-talk/backend/internal/config"
)

// MinIOClient wraps the MinIO client
type MinIOClient struct {
	Client    *minio.Client
	Config    config.MinIOConfig
}

// NewMinIOClient creates a new MinIO client
func NewMinIOClient(cfg config.MinIOConfig) (*MinIOClient, error) {
	client, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create MinIO client: %w", err)
	}

	return &MinIOClient{
		Client: client,
		Config: cfg,
	}, nil
}

// EnsureBuckets creates required buckets if they don't exist
func (m *MinIOClient) EnsureBuckets(ctx context.Context) error {
	buckets := []string{
		m.Config.StickersBucket,
		m.Config.AvatarsBucket,
		m.Config.AttachmentsBucket,
	}

	for _, bucket := range buckets {
		exists, err := m.Client.BucketExists(ctx, bucket)
		if err != nil {
			return fmt.Errorf("failed to check bucket %s: %w", bucket, err)
		}

		if !exists {
			if err := m.Client.MakeBucket(ctx, bucket, minio.MakeBucketOptions{}); err != nil {
				return fmt.Errorf("failed to create bucket %s: %w", bucket, err)
			}
		}
	}

	return nil
}

// UploadFile uploads a file to the specified bucket
func (m *MinIOClient) UploadFile(ctx context.Context, bucket, objectName string, reader io.Reader, size int64, contentType string) error {
	_, err := m.Client.PutObject(ctx, bucket, objectName, reader, size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	return err
}

// DownloadFile downloads a file from the specified bucket
func (m *MinIOClient) DownloadFile(ctx context.Context, bucket, objectName string) (io.ReadCloser, error) {
	return m.Client.GetObject(ctx, bucket, objectName, minio.GetObjectOptions{})
}

// DeleteFile deletes a file from the specified bucket
func (m *MinIOClient) DeleteFile(ctx context.Context, bucket, objectName string) error {
	return m.Client.RemoveObject(ctx, bucket, objectName, minio.RemoveObjectOptions{})
}

// GetFileURL returns the public URL for a file
func (m *MinIOClient) GetFileURL(bucket, objectName string) string {
	return fmt.Sprintf("%s/%s/%s", m.Config.PublicURL, bucket, objectName)
}

// GetPresignedURL generates a presigned URL for private files
func (m *MinIOClient) GetPresignedURL(ctx context.Context, bucket, objectName string, expires time.Duration) (string, error) {
	presignedURL, err := m.Client.PresignedGetObject(ctx, bucket, objectName, expires, url.Values{})
	if err != nil {
		return "", err
	}
	return presignedURL.String(), nil
}

// GetUploadPresignedURL generates a presigned URL for uploading
func (m *MinIOClient) GetUploadPresignedURL(ctx context.Context, bucket, objectName string, expires time.Duration) (string, error) {
	presignedURL, err := m.Client.PresignedPutObject(ctx, bucket, objectName, expires)
	if err != nil {
		return "", err
	}
	return presignedURL.String(), nil
}

// ListFiles lists files in a bucket with optional prefix
func (m *MinIOClient) ListFiles(ctx context.Context, bucket, prefix string) ([]minio.ObjectInfo, error) {
	var objects []minio.ObjectInfo

	objectCh := m.Client.ListObjects(ctx, bucket, minio.ListObjectsOptions{
		Prefix:    prefix,
		Recursive: true,
	})

	for object := range objectCh {
		if object.Err != nil {
			return nil, object.Err
		}
		objects = append(objects, object)
	}

	return objects, nil
}

// FileExists checks if a file exists
func (m *MinIOClient) FileExists(ctx context.Context, bucket, objectName string) (bool, error) {
	_, err := m.Client.StatObject(ctx, bucket, objectName, minio.StatObjectOptions{})
	if err != nil {
		errResponse := minio.ToErrorResponse(err)
		if errResponse.Code == "NoSuchKey" {
			return false, nil
		}
		return false, err
	}
	return true, nil
}
