import 'package:flutter_test/flutter_test.dart';
import 'package:ps12_image_overview/utils/task_lifecycle_manager.dart';
import 'package:sci_tercen_client/sci_client.dart'
    hide ServiceFactory, TaskService;
import 'package:sci_tercen_client/sci_client_service_factory.dart';

/// The state transitions Tercen accepts on a task update
/// (sci_api_model `canChangeTo`). The client does not check them; the
/// server rejects anything else with state.bad.transition.
bool canChangeTo(State from, State to) {
  if (from is InitState || from is PendingState) {
    return to is InitState && from is InitState ||
        to is PendingState ||
        to is RunningState ||
        to is CanceledState ||
        to is FailedState;
  }
  if (from is RunningState) {
    return to is RunningState ||
        to is PendingState ||
        to is DoneState ||
        to is CanceledState ||
        to is FailedState;
  }
  return to.runtimeType == from.runtimeType;
}

/// In-memory task service that applies the server's transition rule.
class FakeTaskService implements TaskService {
  FakeTaskService(this.stored);

  Task stored;
  final List<Type> written = [];

  @override
  Future<Task> get(String id,
      {bool useFactory = true, aclContext}) async {
    final copy = Task.json(stored.toJson());
    return copy;
  }

  @override
  Future<String> update(Task object, {aclContext}) async {
    if (!canChangeTo(stored.state, object.state)) {
      throw ServiceError(400, 'state.bad.transition',
          'state transition ${stored.state}==>${object.state} is not allowed');
    }
    written.add(object.state.runtimeType);
    stored = Task.json(object.toJson());
    return object.rev;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeServiceFactory implements ServiceFactory {
  FakeServiceFactory(this.taskService);

  @override
  final TaskService taskService;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RunComputationTask taskIn(State state) => RunComputationTask()
  ..id = 'task-1'
  ..state = state;

void main() {
  late FakeTaskService tasks;
  late TaskLifecycleManager manager;
  var cancelled = 0;

  void boot(State state) {
    cancelled = 0;
    tasks = FakeTaskService(taskIn(state));
    manager = TaskLifecycleManager(
      taskId: 'task-1',
      serviceFactory: FakeServiceFactory(tasks),
      onCancelled: () => cancelled++,
    );
  }

  tearDown(() => manager.dispose());

  test('a parked (PendingState) task is completed via RunningState', () async {
    boot(PendingState());

    await manager.markTaskComplete();

    expect(tasks.stored.state, isA<DoneState>(),
        reason: 'Tercen rejects PendingState -> DoneState; a single Done '
            'write leaves the step running forever');
    expect(tasks.written, [RunningState, DoneState]);
  });

  test('a task already running is completed directly', () async {
    boot(RunningState());

    await manager.markTaskComplete();

    expect(tasks.stored.state, isA<DoneState>());
    expect(tasks.written, [DoneState]);
  });

  test('a task cancelled before the app loaded is left cancelled', () async {
    boot(CanceledState());

    await manager.markTaskComplete();

    expect(tasks.stored.state, isA<CanceledState>());
    expect(tasks.written, isEmpty);
    expect(cancelled, 1, reason: 'the app cleans up as on any cancel');
  });

  test('a task already done is not written again', () async {
    boot(DoneState());

    await manager.markTaskComplete();

    expect(tasks.written, isEmpty);
  });
}
