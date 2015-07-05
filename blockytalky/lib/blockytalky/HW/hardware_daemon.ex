defmodule Blockytalky.HardwareDaemon do
  use Supervisor
  alias Blockytalky.PythonQuerier, as: PythonQuerier
  require Logger

  @moduledoc """
  The supervisor for all hardware (sensor / motor) hats that can
  be interfaced with.
  Calls to the -hardware_command- interface make the appropriate python api call
  to query the hardware.

  If you are adding a new python hardware api, please implement a setup function
  in the python module.
  Then please add the module name to the environment it is able to be run from
  in the :supported_hardware config variable
  """

  ####
  #config
  @script_dir "#{Application.get_env(:blockytalky, Blockytalky.Endpoint, __DIR__)[:root]}/lib/hw_apis"
  @supported_hardware Application.get_env(:blockytalky, :supported_hardware)
  #these are the sensors and types we will support.  Adding to this list will automatically generate views and options in the web app.
  @basic_sensor_types [
    %{:id => "TYPE_SENSOR_NONE", :label => "None"},
    %{:id => "TYPE_SENSOR_TOUCH", :label => "Touch"},
    %{:id => "TYPE_SENSOR_ULTRASONIC_CONT", :label => "Ultrasonic (Distance)"},
    %{:id => "TYPE_SENSOR_LIGHT_OFF", :label => "Light (ambient)"},
    %{:id => "TYPE_SENSOR_LIGHT_ON", :label => "Light (reflective)"}
  ]
  @sensor_data [
    %{:hw => "mock", :id => "MOCK_1", :label => "Mock 1", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "mock", :id => "MOCK_2", :label => "Mock 2", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "mock", :id => "MOCK_3", :label => "Mock 3", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "mock", :id => "MOCK_4", :label => "Mock 4", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "btbrickpi", :id => "PORT_1", :label => "Sensor Port 1", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "btbrickpi", :id => "PORT_2", :label => "Sensor Port 2", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "btbrickpi", :id => "PORT_3", :label => "Sensor Port 3", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "btbrickpi", :id => "PORT_4", :label => "Sensor Port 4", :type => "sensor", :types => @basic_sensor_types},
    %{:hw => "btbrickpi", :id => "PORT_A", :label => "Motor Port 1", :type => "motor"},
    %{:hw => "btbrickpi", :id => "PORT_B", :label => "Motor Port 2", :type => "motor"},
    %{:hw => "btbrickpi", :id => "PORT_C", :label => "Motor Port 3", :type => "motor"},
    %{:hw => "btbrickpi", :id => "PORT_D", :label => "Motor Port 4", :type => "motor"}
  ]
  ####
  #External API

  def get_sensor_names do
    @sensor_data |> Enum.filter(fn x-> String.to_atom(Map.get(x, :hw)) in @supported_hardware end)
  end
  def get_sensor_type_label_for_id(sensor_id) do
    sensor = @basic_sensor_types |> Enum.find( fn x -> Map.get(x, :id) == sensor_id end)
    Logger.debug "get label for: #{inspect sensor}"
    case sensor do
      nil -> "None"
      map -> Map.get(map, :label, "None")
    end
  end
  @doc """
  When the user hits the stop button, it will stop their code loop from running,
  but also UserCodeChannel will call this method.
  """
  def stop_signal() do
    for sensor <- get_sensor_names do
      #for brickpi: stop all motor_ports
      if sensor[:hw] == "btbrickpi" and sensor[:type] == "motor" do
        Blockytalky.BrickPi.set_motor_value(sensor[:id],0)
      end
      #for grovepi: TODO
      #for music: TODO
      :ok
    end
  end
  ####
  #Supervisor implementation
  # See: Ch. 17 of Programming Elixir
  def start_link() do
    {:ok, _pid} = Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    #create python instances
    Logger.debug "creating python instance at the #{inspect @script_dir} directory"
    #create hw child process instances and spin them up
    hw_children = for hw <- @supported_hardware do
      case hw do
        :btbrickpi ->
            [worker(PythonQuerier, [hw], id: hw, restart: :transient),
             worker(Blockytalky.BrickPiState,[])]
        _ -> worker(PythonQuerier, [hw], id: hw, restart: :transient)
      end
    end
    |> List.flatten
    Logger.debug "Starting HW Workers: #{inspect hw_children}"
    supervise hw_children, strategy: :one_for_one, max_restarts: 5, max_seconds: 1
  end
end
