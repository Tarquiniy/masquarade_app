import 'package:flutter_bloc/flutter_bloc.dart';
import 'domain_event.dart';
import 'domain_state.dart';
import '../../repositories/supabase_repository.dart';

class DomainBloc extends Bloc<DomainEvent, DomainState> {
  final SupabaseRepository repository;

  DomainBloc({required this.repository}) : super(DomainInitial()) {
    on<LoadDomains>(_onLoadDomains);
    on<RefreshDomains>(_onRefreshDomains);
  }

  Future<void> _onLoadDomains(
    LoadDomains event,
    Emitter<DomainState> emit,
  ) async {
    emit(DomainLoading());
    try {
      final domains = await repository.getDomains();
      emit(DomainsLoaded(domains));
    } catch (e) {
      emit(DomainError('Не удалось загрузить домены'));
    }
  }

  Future<void> _onRefreshDomains(
    RefreshDomains event,
    Emitter<DomainState> emit,
  ) async {
    try {
      final domains = await repository.getDomains();
      emit(DomainsLoaded(domains));
    } catch (e) {
      emit(DomainError('Не удалось обновить домены'));
    }
  }
}
