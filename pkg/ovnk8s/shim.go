package ovnk8s

import (
	libovsdbclient "github.com/ovn-org/libovsdb/client"
	ovnconfig "github.com/ovn-org/ovn-kubernetes/go-controller/pkg/config"
	"github.com/ovn-org/ovn-kubernetes/go-controller/pkg/libovsdb"
	"github.com/ovn-org/ovn-kubernetes/go-controller/pkg/metrics"
	"github.com/ovn-org/ovn-kubernetes/go-controller/pkg/util"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/rs/zerolog/log"
	kexec "k8s.io/utils/exec"
)

type Register interface {
	SetExec() error
	RegisterStandaloneOvsMetrics(
		ovsDBClient libovsdbclient.Client,
		metricsScrapeInterval int,
		stopChan <-chan struct{},
	)
	RegisterOvnMetrics(
		stopChan <-chan struct{},
	)
	RegisterOvnControllerMetrics(
		ovsDBClient libovsdbclient.Client,
		metricsScrapeInterval int,
		stopChan <-chan struct{},
	)
	RegisterOVNKubeControllerPerformance(
		nbClient libovsdbclient.Client,
	)
	// RunTimestamp(
	// 	stopChan <-chan struct{},
	// 	sbClient, nbClient libovsdbclient.Client,
	// )
}

type ClientBuilder interface {
	NewOVSClient(address string, stopChan <-chan struct{}) (libovsdbclient.Client, error)
	NewOVNNBClient(address string, stopChan <-chan struct{}) (libovsdbclient.Client, error)
	NewOVNSBClient(address string, stopChan <-chan struct{}) (libovsdbclient.Client, error)
}

type OvnK8sShim interface {
	ClientBuilder
	Register
}

type shim struct{}

func NewOvnK8sShim() OvnK8sShim {
	return &shim{}
}

func (s *shim) SetExec() error {
	if err := util.SetExec(kexec.New()); err != nil {
		log.Error().Err(err).Msg("SetExec error")
		return err
	}
	return nil
}

func (s *shim) RegisterStandaloneOvsMetrics(
	ovsClient libovsdbclient.Client,
	metricsScrapeInterval int,
	stopChan <-chan struct{},
) {
	metrics.RegisterStandaloneOvsMetrics(stopChan)
}

func (s *shim) NewOVSClient(address string, stopChan <-chan struct{}) (libovsdbclient.Client, error) {
	// OVS client is not supported in ovn-kubernetes, using direct command execution
	return nil, nil
}

func (s *shim) NewOVNNBClient(address string, stopChan <-chan struct{}) (libovsdbclient.Client, error) {
	ovnNBClient, err := libovsdb.NewNBClientWithConfig(
		ovnconfig.OvnAuthConfig{
			Scheme:  ovnconfig.OvnDBSchemeUnix,
			Address: address,
		},
		prometheus.DefaultRegisterer,
		stopChan,
	)
	if err != nil {
		return nil, err
	}
	return ovnNBClient, nil
}

func (s *shim) NewOVNSBClient(address string, stopChan <-chan struct{}) (libovsdbclient.Client, error) {
	ovnSBClient, err := libovsdb.NewSBClientWithConfig(
		ovnconfig.OvnAuthConfig{
			Scheme:  ovnconfig.OvnDBSchemeUnix,
			Address: address,
		},
		prometheus.DefaultRegisterer,
		stopChan,
	)
	if err != nil {
		return nil, err
	}
	return ovnSBClient, nil
}

func (s *shim) RegisterOvnControllerMetrics(
	ovsDBClient libovsdbclient.Client,
	metricsScrapeInterval int,
	stopChan <-chan struct{},
) {
	metrics.RegisterOvnControllerMetrics(stopChan)
}

func (s *shim) RegisterOvnMetrics(
	stopChan <-chan struct{},
) {
	metrics.RegisterOvnMetrics(stopChan)
}

func (s *shim) RegisterOVNKubeControllerPerformance(
	nbClient libovsdbclient.Client,
) {
	metrics.RegisterOVNKubeControllerPerformance(nbClient)
}

func (s *shim) RunTimestamp(
	stopChan <-chan struct{},
	sbClient, nbClient libovsdbclient.Client,
) {
	metrics.RunTimestamp(stopChan, sbClient, nbClient)
}
